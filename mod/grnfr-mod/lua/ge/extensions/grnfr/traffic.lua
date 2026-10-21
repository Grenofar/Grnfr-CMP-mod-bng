-- Trafic adaptatif (EN DÉVELOPPEMENT) : baisse le nombre de voitures en circulation / garées tant que les FPS
-- sont sous le minimum choisi, puis les remonte (au plus jusqu'au niveau de départ) si les FPS sont confortables.
-- Si même sans aucun trafic le PC n'atteint pas ce minimum : état « impossible », niveau de départ restauré.
-- TOUS les noms d'API (gameplay_traffic.*, gameplay_parking.*) sont des hypothèses non vérifiées en jeu :
-- si elles ne répondent pas, l'état devient « unavailable ».
local M = {}
local state = 'off' -- off | running | impossible | unavailable
local base, cur = nil, nil
local acc, cool, lowT, sinceDown = 0, 0, 0, 999
local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local lastLog = 0

local function num(x) x = tonumber(x) if x and x >= 0 then return math.floor(x) end end

local function readAmounts()
  local a, p
  pcall(function()
    local v = gameplay_traffic.getTrafficVars()
    if type(v) == 'table' then a, p = num(v.activeAmount), num(v.parkedAmount) end
  end)
  if not a then pcall(function() a = num(gameplay_traffic.getNumOfTraffic()) end) end
  if not p then
    pcall(function()
      local l = gameplay_parking.getParkedCarsList and gameplay_parking.getParkedCarsList()
      if type(l) == 'table' then local n = 0 for _ in pairs(l) do n = n + 1 end p = n end
    end)
  end
  if a then return { active = a, parked = p or 0 } end
end

-- Retire explicitement les voitures en trop (les plus éloignées du joueur) si l'API ne le fait pas d'elle-même.
local function trimTraffic(n)
  pcall(function()
    local ids = gameplay_traffic.getTrafficList and gameplay_traffic.getTrafficList()
    if type(ids) ~= 'table' then return end
    local list = {}
    for _, id in pairs(ids) do list[#list + 1] = id end
    if #list <= n then return end
    local pv = be:getPlayerVehicle(0)
    local pp = pv and pv:getPosition()
    table.sort(list, function(x, y)
      local ox, oy = be:getObjectByID(x), be:getObjectByID(y)
      if not (ox and oy and pp) then return false end
      return (ox:getPosition() - pp):length() > (oy:getPosition() - pp):length()
    end)
    for i = 1, #list - n do
      local id = list[i]
      pcall(function() gameplay_traffic.removeTraffic(id) end)
      local o = be:getObjectByID(id)
      if o then o:delete() end
    end
  end)
end

local function apply(a, p)
  pcall(function() gameplay_traffic.setTrafficVars({ activeAmount = a, parkedAmount = p }) end)
  pcall(function() if gameplay_parking and gameplay_parking.setActiveAmount then gameplay_parking.setActiveAmount(p) end end)
  trimTraffic(a)
  cur = { active = a, parked = p }
  if os.time() - lastLog >= 10 then -- at most one line every 10 seconds
    lastLog = os.time()
    slog('info', string.format('Adaptive traffic: now %d moving cars and %d parked cars.', a, p))
  end
end

function M.setEnabled(on)
  if on then
    pcall(function() if not gameplay_traffic then extensions.load('gameplay_traffic') end end)
    local r = gameplay_traffic and readAmounts()
    if not r then state = 'unavailable'; base, cur = nil, nil; slog('warn', 'Adaptive traffic cannot start: the game traffic system is not available on this map or game version.'); return end
    base, cur = { active = r.active, parked = r.parked }, { active = r.active, parked = r.parked }
    acc, cool, lowT, sinceDown = 0, 2, 0, 999
    state = 'running'
    slog('info', string.format('Adaptive traffic is ON. Starting traffic: %d moving cars, %d parked cars.', base.active, base.parked))
  else
    if state == 'running' and base then
      apply(base.active, base.parked)
      slog('info', 'Adaptive traffic is OFF. The original traffic amounts were restored.')
    end
    state = 'off'; base, cur = nil, nil
  end
end

-- À appeler à chaque image : dt en secondes, avg = FPS moyens sur 1 s (nil si invalide), target = FPS minimum voulu.
function M.update(dt, avg, target)
  if state ~= 'running' or not cur or not avg or not target then return end
  acc = acc + (tonumber(dt) or 0)
  if acc < 1 then return end -- une décision par seconde
  acc = 0
  sinceDown = sinceDown + 1
  if cool > 0 then cool = cool - 1 return end
  if avg < target then
    if cur.active > 0 or cur.parked > 0 then
      local step = ((target - avg) / target > 0.3) and 2 or 1
      local a, p = cur.active, cur.parked
      for _ = 1, step do
        if p > 0 and p >= a then p = p - 1 elseif a > 0 then a = a - 1 elseif p > 0 then p = p - 1 end
      end
      apply(a, p)
      cool, lowT, sinceDown = 3, 0, 0 -- laisse les FPS se stabiliser avant la décision suivante
    else
      lowT = lowT + 1
      if lowT >= 4 then -- 0 voiture et toujours sous le minimum : le PC ne peut pas faire tourner ce minimum
        apply(base.active, base.parked)
        state = 'impossible'
        slog('warn', 'Adaptive traffic gave up: FPS stayed under your minimum even with no traffic. The original traffic amounts were restored.')
      end
    end
  elseif avg > target * 1.25 and sinceDown > 20 and (cur.active < base.active or cur.parked < base.parked) then
    local a, p = cur.active, cur.parked
    if a < base.active then a = a + 1 elseif p < base.parked then p = p + 1 end
    apply(a, p)
    cool = 6
  else
    lowT = 0
  end
end

function M.reset() state, base, cur = 'off', nil, nil end
function M.status() return { state = state, active = cur and cur.active or 0, parked = cur and cur.parked or 0,
  baseActive = base and base.active or 0, baseParked = base and base.parked or 0 } end
return M
