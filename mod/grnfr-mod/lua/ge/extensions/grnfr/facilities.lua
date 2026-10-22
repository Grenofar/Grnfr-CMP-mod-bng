-- GRNFR Online : les vrais garages de la carte (ceux de la carrière du jeu : Belasco City Garage, Chinatown Garage...).
--
-- Source : les fichiers de la carte que la carrière lit elle-même (levels/<carte>/facilities/*.facilities.json pour les
-- garages et leurs ordinateurs, facilities.sites.json pour les places de parking). On passe d'abord par le module du
-- jeu freeroam_facilities (getFacilitiesByType / getParkingSpotsForFacility), sinon on lit les fichiers nous-mêmes.
-- Position de l'ordinateur (= notre tablette) : l'objet « porte » de l'ordinateur dans la carte (scenetree), sinon la
-- première place de parking du garage. Tout est sous pcall : API du jeu non vérifiées en jeu (relevées dans le code
-- de la carrière), et une carte sans garages renvoie simplement une liste vide (pas de garage au hasard sur la route).
local M = {}

local cache = { level = nil, list = nil }
local dpCache = { level = nil, list = nil } -- points de livraison (deliveryProvider), phase 2

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local function v3(p)
  if type(p) ~= 'table' then
    if p and p.x then return vec3(p.x, p.y, p.z) end
    return nil
  end
  if p.x then return vec3(p.x, p.y, p.z) end
  if p[1] then return vec3(p[1], p[2], p[3]) end
end
local function q4(r)
  if type(r) == 'table' and r[4] then return quat(r[1], r[2], r[3], r[4]) end
  if r and r.w then return r end
end

local function objPos(name)
  local ok, p = pcall(function() local o = scenetree.findObject(name) return o and o:getPosition() end)
  if ok and p then return vec3(p.x, p.y, p.z) end
end

-- Via le module de la carrière (chargé à la demande).
local function fromGame(level)
  pcall(function() if not rawget(_G, 'freeroam_facilities') then extensions.load('freeroam_facilities') end end)
  local fac = rawget(_G, 'freeroam_facilities')
  if not fac or not fac.getFacilitiesByType then return nil end
  local okG, garages = pcall(fac.getFacilitiesByType, 'garage', level)
  if not okG or type(garages) ~= 'table' then return nil end
  local okC, computers = pcall(fac.getFacilitiesByType, 'computer', level)
  if not okC or type(computers) ~= 'table' then computers = {} end
  local out = {}
  for _, g in ipairs(garages) do
    local spots = {}
    pcall(function()
      for _, s in ipairs(fac.getParkingSpotsForFacility(g) or {}) do
        local p = v3(s.pos)
        if p then spots[#spots + 1] = { pos = p, rot = q4(s.rot) } end
      end
    end)
    out[#out + 1] = { id = g.id, name = g.name or g.id, spots = spots, computers = computers }
  end
  return out
end

-- Repli : lecture directe des fichiers de la carte.
local function fromFiles(level)
  local dir = '/levels/' .. level .. '/'
  local garages, computers = {}, {}
  pcall(function()
    for _, file in ipairs(FS:findFiles(dir .. 'facilities/', '*.facilities.json', -1, false, true) or {}) do
      local d = jsonReadFile(file)
      if type(d) == 'table' then
        for _, g in ipairs(d.garages or {}) do garages[#garages + 1] = g end
        for _, c in ipairs(d.computers or {}) do computers[#computers + 1] = c end
      end
    end
  end)
  if #garages == 0 then return nil end
  local byName = {}
  pcall(function()
    local sites = jsonReadFile(dir .. 'facilities.sites.json')
    for _, s in ipairs((sites and sites.parkingSpots) or {}) do if s.name then byName[s.name] = s end end
  end)
  local out = {}
  for _, g in ipairs(garages) do
    local spots = {}
    for _, n in ipairs(g.parkingSpotNames or {}) do
      local s = byName[n]
      local p = s and v3(s.pos)
      if p then spots[#spots + 1] = { pos = p, rot = q4(s.rot) } end
    end
    out[#out + 1] = { id = g.id, name = g.name or g.id, spots = spots, computers = computers }
  end
  return out
end

-- Liste des garages : { id, name, spots = { {pos, rot} }, tablet = vec3, hasComputer }.
function M.garages()
  local level = grnfr_places.level()
  if cache.level == level and cache.list then return cache.list end
  local raw = fromGame(level) or fromFiles(level) or {}
  local list = {}
  for _, g in ipairs(raw) do
    local tablet, hasComputer
    for _, c in ipairs(g.computers or {}) do
      if c.garageId == g.id then
        for _, door in ipairs(c.doors or {}) do
          tablet = tablet or (type(door) == 'table' and (objPos(door[1]) or objPos(door[2])))
        end
        hasComputer = true
      end
    end
    tablet = tablet or (g.spots[1] and g.spots[1].pos)
    if tablet then list[#list + 1] = { id = g.id, name = g.name, spots = g.spots, tablet = tablet, hasComputer = hasComputer == true } end
  end
  -- garages avec ordinateur d'abord (un vrai poste de travail = la tablette)
  table.sort(list, function(a, b) if a.hasComputer ~= b.hasComputer then return a.hasComputer end return a.name < b.name end)
  if #list > 0 then slog('info', 'Garages: ' .. #list .. ' real garages found on ' .. level .. '.')
  else slog('warn', 'Garages: no garage found on ' .. level .. '.') end
  cache.level, cache.list = level, list
  return list
end

local function d2(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end
M.dist = d2

-- Le garage dont la tablette (ou une place) est à moins de `within` m de pos.
function M.at(pos, within)
  if not pos then return nil end
  within = within or 30
  local best, bd
  for _, g in ipairs(M.garages()) do
    local d = d2(g.tablet, pos)
    for _, s in ipairs(g.spots) do d = math.min(d, d2(s.pos, pos)) end
    if d <= within and (not bd or d < bd) then best, bd = g, d end
  end
  return best
end

-- Points de livraison (deliveryProvider) de la carte, pour les missions de colis (phase 2, TODO point 2) : liste de
-- points nommés avec leur position. Même principe que les garages (module carrière, repli = liste vide, jamais un
-- point au hasard) ; API `getFacilitiesByType('deliveryProvider', ...)` non vérifiée en jeu dans cette session.
function M.deliveryPoints()
  local level = grnfr_places.level()
  if dpCache.level == level and dpCache.list then return dpCache.list end
  local out = {}
  pcall(function()
    if not rawget(_G, 'freeroam_facilities') then extensions.load('freeroam_facilities') end
    local fac = rawget(_G, 'freeroam_facilities')
    if not fac or not fac.getFacilitiesByType then return end
    for _, f in ipairs(fac.getFacilitiesByType('deliveryProvider', level) or {}) do
      local pos
      pcall(function()
        for _, s in ipairs(fac.getParkingSpotsForFacility(f) or {}) do
          if not pos then pos = v3(s.pos) end
        end
      end)
      if pos then out[#out + 1] = { id = f.id, name = f.name or f.id, pos = pos } end
    end
  end)
  if #out > 0 then slog('info', 'Deliveries: ' .. #out .. ' delivery points found on ' .. level .. '.')
  else slog('warn', 'Deliveries: no delivery point found on ' .. level .. ' (getFacilitiesByType unverified here).') end
  dpCache.level, dpCache.list = level, out
  return out
end

function M.reset() cache, dpCache = { level = nil, list = nil }, { level = nil, list = nil } end

return M
