-- GRNFR Online : trafic partagé (2 voitures IA) par serveur de jeu.
-- Le joueur présent depuis le plus longtemps sur le serveur ("hôte", décidé par le serveur à chaque appel de
-- server_sync, voir supabase/migrations/0003_convoy.sql) fait rouler 2 voitures IA et envoie leur position
-- comme pour sa propre position (ghosts.lua). Les autres joueurs du serveur les affichent en fantômes (comme
-- les autres joueurs), sans collision : ils ne les pilotent pas. Si l'hôte quitte le serveur, le joueur
-- suivant par ancienneté devient hôte et fait apparaître ses propres voitures à sa place.
-- Toutes les API du jeu sont sous pcall (hypothèses non vérifiées en jeu), comme le reste du mod.
local M = {}

local joined = false
local isHost = false
local cars = {}         -- 1..2 -> { obj = id, model, config } (chez l'hôte)
local ghosts = {}       -- 1..2 -> { obj = id, key, pos } (chez les autres)
local selfAcc, clock = 0, 0
local lastRemote = nil  -- dernier "convoy" reçu du serveur (quand on n'est pas hôte)
local lastRecvClock = 0
local lastSpawnTry = -99
local MODELS = { 'covet', 'pickup' } -- repli si aucune config "Car" n'est trouvée
local SEND_INTERVAL = 0.3

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local function num(x, d) x = tonumber(x) if x ~= x or x == nil then return d end return x end
local function playerVeh() local ok, v = pcall(function() return be:getPlayerVehicle(0) end) if ok then return v end end
local function deleteObj(id) pcall(function() local o = be:getObjectByID(id) if o then o:delete() end end) end

function M.setServer(isJoined)
  isJoined = isJoined == true
  if isJoined ~= joined then slog('info', isJoined and 'Shared traffic: joined a game server.' or 'Shared traffic: left the game server.') end
  joined = isJoined
  if not joined then M.reset() end
  return true
end

-- Reçu de l'interface après chaque server_sync : { isHost = bool, convoy = [...] ou nil }
function M.onSync(payload)
  if not joined then return true end
  local ok, d = pcall(jsonDecode, payload or '{}')
  if not ok or type(d) ~= 'table' then return true end
  local wasHost = isHost
  isHost = d.isHost == true
  if isHost and not wasHost then
    slog('info', 'Shared traffic: you are now hosting the 2 traffic cars for this server.')
    M.despawnGhosts()
  elseif not isHost and wasHost then
    slog('info', 'Shared traffic: another player is now hosting the traffic cars.')
    M.despawnCars()
  end
  if not isHost then
    lastRemote = type(d.convoy) == 'table' and d.convoy or nil
    lastRecvClock = clock
  end
  return true
end

-- ------------------------------------------------------------------ hôte : pilotage des 2 voitures
local function configsFiltered()
  local ok, l = pcall(function() return core_vehicles.getConfigList() end)
  if not ok or type(l) ~= 'table' then return nil end
  l = l.configs or l
  local out = {}
  for _, c in pairs(l) do
    if type(c) == 'table' and c.model_key then
      local t = c.Type or (c.aggregates and c.aggregates.Type)
      local isCar = true
      if type(t) == 'string' then isCar = (t == 'Car') elseif type(t) == 'table' then isCar = (t.Car ~= nil) end
      local key = tostring(c.config_key or c.key or ''):lower()
      if isCar and not key:find('police') and not key:find('trailer') then out[#out + 1] = c end
    end
  end
  if #out > 0 then return out end
end

local function pickTwo()
  local list = configsFiltered()
  if list and #list >= 2 then
    local a = list[math.random(#list)]
    local b = a
    for _ = 1, 6 do
      b = list[math.random(#list)]
      if b.model_key ~= a.model_key or (b.config_key or b.key) ~= (a.config_key or a.key) then break end
    end
    return { { model = a.model_key, config = a.config_key or a.key }, { model = b.model_key, config = b.config_key or b.key } }
  end
  return { { model = MODELS[1] }, { model = MODELS[2] } }
end

local function spawnCars()
  local pv = playerVeh()
  if not pv then return end
  local specs = pickTwo()
  local ok = pcall(function()
    local pos, dir, up = pv:getPosition(), pv:getDirectionVector(), pv:getDirectionVectorUp()
    local right = dir:cross(up):normalized()
    local offsets = { right * 8 + dir * 10, right * -8 + dir * 16 }
    for i = 1, 2 do
      local spec = specs[i]
      local ok2, obj = pcall(function()
        local opts = { autoEnterVehicle = false, vehicleName = 'grnfr_traffic_' .. i }
        if spec.config and spec.config ~= '' then opts.config = spec.config end
        opts.pos = pos + offsets[i]
        opts.rot = quatFromDir(dir, up)
        return core_vehicles.spawnNewVehicle(spec.model, opts)
      end)
      if ok2 and obj then
        local id = type(obj) == 'number' and obj or obj:getID()
        cars[i] = { obj = id, model = spec.model, config = spec.config }
        pcall(function() be:getObjectByID(id):queueLuaCommand("if ai then ai.setMode('traffic') end") end)
      else
        slog('warn', 'Shared traffic: the game refused to spawn traffic car ' .. i .. '.')
      end
    end
  end)
  if ok then slog('info', 'Shared traffic: 2 traffic cars spawned (you are hosting them).') end
end

function M.despawnCars()
  for _, c in pairs(cars) do if c.obj then deleteObj(c.obj) end end
  cars = {}
end

local function carsAlive()
  if not cars[1] or not cars[2] then return false end
  for _, c in pairs(cars) do
    local ok, o = pcall(function() return be:getObjectByID(c.obj) end)
    if not ok or not o then return false end
  end
  return true
end

local function updateHost(dt)
  if not carsAlive() then
    if lastSpawnTry + 3 <= clock then
      lastSpawnTry = clock
      M.despawnCars()
      spawnCars()
    end
    return
  end
  selfAcc = selfAcc + dt
  if selfAcc < SEND_INTERVAL then return end
  selfAcc = 0
  local out = {}
  for i = 1, 2 do
    local c = cars[i]
    local ok, st = pcall(function()
      local o = be:getObjectByID(c.obj)
      local p, vel, q = o:getPosition(), o:getVelocity(), o:getRotation()
      return { pos = { x = p.x, y = p.y, z = p.z }, vel = { vel.x, vel.y, vel.z }, rot = { q.x, q.y, q.z, q.w },
               veh = { model = c.model, config = c.config } }
    end)
    if ok and st then out[#out + 1] = st end
  end
  if #out > 0 then guihooks.trigger('GRNFRConvoySelf', out) end
end

-- ------------------------------------------------------------------ invité : fantômes du trafic de l'hôte
local function ensureGhost(i, entry)
  local veh = entry.veh
  if type(veh) ~= 'table' or type(veh.model) ~= 'string' or veh.model == '' then return end
  local key = veh.model .. '|' .. tostring(veh.config or '')
  local g = ghosts[i]
  if g and g.obj and g.key == key then
    local ok, o = pcall(function() return be:getObjectByID(g.obj) end)
    if ok and o then return o end
    g.obj = nil
  end
  if g and g.obj and g.key ~= key then deleteObj(g.obj); g.obj = nil end
  local ok, obj = pcall(function()
    local opts = { autoEnterVehicle = false, vehicleName = 'grnfr_traffic_ghost_' .. i }
    if veh.config and veh.config ~= '' then opts.config = veh.config end
    local p = entry.pos
    opts.pos = vec3(num(p.x, 0), num(p.y, 0), num(p.z, 0) + 0.3)
    if type(entry.rot) == 'table' and #entry.rot == 4 then opts.rot = quat(entry.rot[1], entry.rot[2], entry.rot[3], entry.rot[4]) end
    return core_vehicles.spawnNewVehicle(veh.model, opts)
  end)
  if not ok or not obj then return end
  local id = type(obj) == 'number' and obj or obj:getID()
  ghosts[i] = { obj = id, key = key, pos = nil }
  pcall(function() be:getObjectByID(id):queueLuaCommand('if obj.setGhostEnabled then obj:setGhostEnabled(true) end') end)
  return be:getObjectByID(id)
end

function M.despawnGhosts()
  for _, g in pairs(ghosts) do if g.obj then deleteObj(g.obj) end end
  ghosts = {}
end

local function updateGuest(dt)
  if not lastRemote then
    if next(ghosts) then M.despawnGhosts() end
    return
  end
  if clock - lastRecvClock > 5 then -- plus de nouvelles de l'hôte depuis trop longtemps : on efface les fantômes
    M.despawnGhosts(); lastRemote = nil
    return
  end
  for i, entry in ipairs(lastRemote) do
    if i <= 2 and type(entry) == 'table' and type(entry.pos) == 'table' then
      local o = ensureGhost(i, entry)
      if o then
        local p = entry.pos
        local target = vec3(num(p.x, 0), num(p.y, 0), num(p.z, 0))
        local g = ghosts[i]
        local cur = g.pos
        if not cur or (cur - target):length() > 30 then cur = target
        else cur = cur + (target - cur) * math.min(1, dt * 12) end
        g.pos = cur
        local rot = type(entry.rot) == 'table' and entry.rot or { 0, 0, 0, 1 }
        pcall(function() o:setPositionRotation(cur.x, cur.y, cur.z, num(rot[1], 0), num(rot[2], 0), num(rot[3], 0), num(rot[4], 1)) end)
      end
    end
  end
end

function M.update(dt)
  clock = clock + dt
  if not joined then return end
  if isHost then updateHost(dt) else updateGuest(dt) end
end

function M.status() return { joined = joined, host = isHost } end

function M.reset()
  M.despawnCars(); M.despawnGhosts()
  isHost = false; lastRemote = nil; selfAcc = 0
end

return M
