-- GRNFR Online : lieux crédibles pour les courses (taxi, bus).
-- Un passager n'apparaît jamais « au milieu de nulle part » : on ne tire que des points du réseau routier de la carte
-- (map.getMap().nodes), ou des lieux nommés fournis par le jeu / par le joueur :
--   settings/grnfr/places_<carte>.json  =  [ { "name": "Gare", "x": 1.0, "y": 2.0, "z": 3.0 }, ... ]
-- Les API du jeu (map.*, gameplay_rawPois) sont des hypothèses non vérifiées : tout est sous pcall,
-- et l'absence d'une API retombe sur un comportement plus simple (jamais d'erreur visible).
local M = {}

local cache = { level = nil, nodes = nil }

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

function M.level()
  local ok, n = pcall(function() return getMissionFilename() end)
  if ok and type(n) == 'string' then
    local lv = n:match('levels/([^/\\]+)')
    if lv then return lv end
  end
  return 'unknown'
end

local function playerPos()
  local ok, p = pcall(function() return be:getPlayerVehicle(0):getPosition() end)
  if ok and p then return p end
end
M.playerPos = playerPos

local function xyz(p) return { x = p.x, y = p.y, z = p.z } end
M.xyz = xyz

-- Nœuds de route utilisables : assez larges, reliés à au moins un autre nœud.
local function roadNodes()
  local lv = M.level()
  if cache.level == lv and cache.nodes then return cache.nodes end
  local list = {}
  pcall(function()
    local nodes = map.getMap().nodes
    for id, n in pairs(nodes) do
      local links = 0
      if n.links then for _ in pairs(n.links) do links = links + 1 end end
      if n.pos and (n.radius or 0) >= 1.5 and links >= 1 then list[#list + 1] = { id = id, pos = n.pos } end
    end
  end)
  cache.level, cache.nodes = lv, list
  return list
end

local function dist2(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end
M.dist = dist2

-- Point de route au hasard à une distance (à vol d'oiseau) comprise entre minD et maxD de `origin`.
function M.randomNear(origin, minD, maxD)
  local nodes = roadNodes()
  if #nodes == 0 or not origin then return nil end
  local cands = {}
  for _, n in ipairs(nodes) do
    local d = dist2(n.pos, origin)
    if d >= minD and d <= maxD then cands[#cands + 1] = n end
  end
  if #cands == 0 then -- carte petite ou joueur loin des routes : on prend le nœud le plus proche de la fenêtre demandée
    local best, bd
    for _, n in ipairs(nodes) do
      local d = math.abs(dist2(n.pos, origin) - (minD + maxD) / 2)
      if not bd or d < bd then best, bd = n, d end
    end
    if not best then return nil end
    cands = { best }
  end
  local n = cands[math.random(#cands)]
  return { x = n.pos.x, y = n.pos.y, z = n.pos.z, node = n.id }
end

-- Nœud de route le plus proche d'une position (pour guider une voiture IA).
function M.closestNode(pos)
  local ok, a = pcall(function() return (map.findClosestRoad(pos)) end)
  if ok and a then return a end
end

-- Longueur du trajet routier entre deux points {x,y,z,node}, en mètres (ligne droite x 1,3 si le calcul échoue).
function M.routeLength(a, b)
  local straight = dist2(a, b)
  local na = a.node or M.closestNode(vec3(a.x, a.y, a.z))
  local nb = b.node or M.closestNode(vec3(b.x, b.y, b.z))
  local ok, total = pcall(function()
    local path = map.getPath(na, nb)
    if type(path) ~= 'table' or #path < 2 then return nil end
    local nodes, sum = map.getMap().nodes, 0
    for i = 2, #path do sum = sum + (nodes[path[i]].pos - nodes[path[i - 1]].pos):length() end
    return sum
  end)
  if ok and type(total) == 'number' and total >= straight * 0.9 then return math.floor(total) end
  return math.floor(straight * 1.3)
end

-- ------------------------------------------------------------------ lieux nommés
local function customPath() return 'settings/grnfr/places_' .. M.level() .. '.json' end

local function readCustom()
  local out = {}
  pcall(function()
    local d = jsonReadFile(customPath())
    if type(d) == 'table' then
      for _, p in ipairs(d) do
        if type(p) == 'table' and type(p.x) == 'number' and type(p.y) == 'number' then
          out[#out + 1] = { name = tostring(p.name or 'Lieu'), x = p.x, y = p.y, z = tonumber(p.z) or 0 }
        end
      end
    end
  end)
  return out
end

-- Lieux d'intérêt connus du jeu (garages, stations...). API non vérifiée : on lit ce qu'on peut, sans insister.
local function gamePois()
  local out = {}
  pcall(function()
    local list = gameplay_rawPois and gameplay_rawPois.getRawPoiListByLevel and gameplay_rawPois.getRawPoiListByLevel(M.level())
    if type(list) ~= 'table' then return end
    for _, p in pairs(list) do
      local pos = p.pos or (p.markerInfo and p.markerInfo.walkingMarker and p.markerInfo.walkingMarker.pos)
        or (p.markerInfo and p.markerInfo.bigmapMarker and p.markerInfo.bigmapMarker.pos)
      local name = p.name or p.id
      if pos and name then
        local n = tostring(name)
        if n:find('^[%w_%.]+$') and n:find('%.') then n = n:match('([^%.]+)$') end -- clé de traduction non résolue : on garde la fin
        out[#out + 1] = { name = n, x = pos.x, y = pos.y, z = pos.z }
      end
    end
  end)
  return out
end

M.pois = gamePois -- lieux nommés du jeu (garages, stations...), réutilisé par grnfr_garage pour trouver un point de garage

-- Destinations proposées au joueur : lieux nommés les plus proches, complétés par des points de route.
function M.list(origin, count)
  count = count or 8
  origin = origin or playerPos()
  local all = readCustom()
  for _, p in ipairs(gamePois()) do all[#all + 1] = p end
  local res = {}
  if origin then
    for _, p in ipairs(all) do
      local d = dist2(p, origin)
      if d >= 300 then res[#res + 1] = { name = p.name, x = p.x, y = p.y, z = p.z, d = d, named = true } end
    end
    table.sort(res, function(a, b) return a.d < b.d end)
    while #res > count do table.remove(res) end
    local tries = 0
    while #res < count and tries < 40 do
      tries = tries + 1
      local n = M.randomNear(origin, 500, 6000)
      if not n then break end
      res[#res + 1] = { name = '', x = n.x, y = n.y, z = n.z, node = n.node, d = dist2(n, origin) }
    end
    table.sort(res, function(a, b) return a.d < b.d end)
  end
  local i = 0
  for _, r in ipairs(res) do
    if r.name == '' then i = i + 1; r.name = 'Point ' .. string.char(64 + i) end
    r.d = math.floor(r.d)
  end
  return res
end

-- Outil de développement : enregistre la position actuelle comme lieu nommé de la carte.
function M.addCurrent(name)
  local p = playerPos()
  if not p then return false end
  local list = readCustom()
  list[#list + 1] = { name = tostring(name or 'Lieu'), x = p.x, y = p.y, z = p.z }
  local ok = pcall(jsonWriteFile, customPath(), list, true)
  if ok then slog('info', 'Place saved: ' .. tostring(name)) end
  return ok
end

function M.reset() cache.level, cache.nodes = nil, nil end

return M
