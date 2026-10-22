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

-- Un garage réel mais rattaché à un circuit/une piste de drag (pas un vrai garage résidentiel/commercial) :
-- repéré à l'utilisateur en jeu comme « une sorte de petite tente pour les courses » (alderDragwayGarage sur
-- west_coast_usa, confirmé en inspectant levels/west_coast_usa/facilities/facilities.facilities.json — un vrai
-- garage du jeu, avec son vrai ordinateur, juste au bord d'une piste de drag plutôt que dans un vrai bâtiment).
-- On ne l'exclut pas (ce serait inventer un garage ailleurs) : on le passe juste en dernier, comme un garage
-- sans ordinateur, pour qu'un vrai garage "normal" soit toujours préféré quand il y en a un de libre.
local function isTrackLike(id)
  id = tostring(id or ''):lower()
  return id:find('dragway') or id:find('racetrack') or id:find('raceway') or id:find('rallycross') or id:find('drift')
end

-- Liste des garages : { id, name, spots = { {pos, rot} }, tablet = vec3, hasComputer, trackLike }.
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
    if tablet then
      list[#list + 1] = { id = g.id, name = g.name, spots = g.spots, tablet = tablet, hasComputer = hasComputer == true,
        trackLike = isTrackLike(g.id) ~= nil }
    end
  end
  -- garages avec ordinateur d'abord (un vrai poste de travail = la tablette), ceux liés à un circuit en dernier
  table.sort(list, function(a, b)
    if a.hasComputer ~= b.hasComputer then return a.hasComputer end
    if a.trackLike ~= b.trackLike then return not a.trackLike end
    return a.name < b.name
  end)
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

-- Vraies lignes de bus de la carte (grand chantier Phase E, 22/10/2026) : lues exactement comme le fait le jeu
-- lui-même dans core_busRouteManager.lua (lua/ge/extensions/core/busRouteManager.lua, inspecté sur l'installation
-- BeamNG de cette machine) — jamais vérifié depuis NOTRE mod, mais c'est du code copié du vrai module du jeu :
--   * les lignes (ordre des arrêts, nom de direction) viennent de levels/<carte>/buslines/*.buslines.json ;
--   * les positions des arrêts viennent des objets de la scène (SimGroup "busstops", des BeamNGTrigger de type
--     "busstop", chacun avec un nom technique ET un nom affiché "stopName" plus lisible).
-- Une carte sans ligne de bus renvoie une liste vide (bus.lua utilise alors son ancienne génération d'arrêts au
-- hasard le long des routes, jamais de ligne inventée de toutes pièces).
local blCache = { level = nil, list = nil }

function M.busLines()
  local level = grnfr_places.level()
  if blCache.level == level and blCache.list then return blCache.list end
  local dir = '/levels/' .. level .. '/'
  local routes = {}
  pcall(function()
    for _, file in ipairs(FS:findFiles(dir .. 'buslines/', '*.buslines.json', -1, false, true) or {}) do
      local d = jsonReadFile(file)
      if type(d) == 'table' and type(d.routes) == 'table' then
        for _, r in ipairs(d.routes) do routes[#routes + 1] = r end
      end
    end
  end)
  local stops = {}
  pcall(function()
    local folder = scenetree.findObject('busstops')
    if not folder then return end
    for i = 0, folder:getCount() - 1 do
      local trig = folder:getObject(i)
      if trig then
        local okCls, cls = pcall(function() return trig:getClassName() end)
        if okCls and cls == 'BeamNGTrigger' then
          local up = (Sim and Sim.upcast and Sim.upcast(trig)) or trig
          local okTy, ty = pcall(function() return up.type end)
          if okTy and ty == 'busstop' then
            local okN, name = pcall(function() return up.name end)
            local okS, sname = pcall(function() return up.stopName end)
            local okP, pos = pcall(function() return up:getPosition() end)
            if okN and type(name) == 'string' and okP and pos then
              stops[name] = { pos = vec3(pos.x, pos.y, pos.z), name = (okS and type(sname) == 'string' and sname ~= '' and sname) or name }
            end
          end
        end
      end
    end
  end)
  local out = {}
  for _, r in ipairs(routes) do
    local tasklist = {}
    for _, stopId in ipairs(r.tasklist or {}) do
      local s = stops[stopId]
      if s then tasklist[#tasklist + 1] = { x = s.pos.x, y = s.pos.y, z = s.pos.z, name = s.name } end
    end
    if #tasklist >= 3 then
      out[#out + 1] = { routeID = r.routeID, variance = r.variance, direction = r.direction, stops = tasklist }
    end
  end
  if #out > 0 then slog('info', 'Bus: ' .. #out .. ' real bus line(s) found on ' .. level .. '.')
  else slog('info', 'Bus: no real bus line found on ' .. level .. ' (synthetic stops will be used).') end
  blCache.level, blCache.list = level, out
  return out
end

function M.reset() cache, dpCache, blCache = { level = nil, list = nil }, { level = nil, list = nil }, { level = nil, list = nil } end

return M
