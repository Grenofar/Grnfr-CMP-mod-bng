-- GRNFR Online : en rejoignant un serveur, on arrive sur la carte des autres joueurs, à côté d'eux.
--
-- L'interface (net.js) demande au serveur où sont les joueurs déjà présents, puis appelle go(level, pos) :
--   * même carte que maintenant : on place simplement la voiture du joueur à côté de pos ;
--   * autre carte (ou menu principal) : on charge cette carte en jeu libre, puis on place la voiture une fois
--     la carte prête (onClientStartMission + attente du véhicule du joueur).
-- Les API de chargement / téléportation (freeroam_freeroam.startFreeroamByName, core_levels.startLevel,
-- spawn.safeTeleport) sont des hypothèses non vérifiées en jeu : tout est sous pcall, plusieurs noms sont essayés.
local M = {}

local target = nil      -- { level, pos } en attente d'arrivée sur la carte
local waitAcc = 0
local WAIT_MAX = 60     -- s : au-delà, on abandonne le placement (carte jamais chargée, véhicule jamais apparu)
local SETTLE = 2        -- s : après l'apparition du véhicule, on laisse la carte finir de se poser

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local function L(fr, en) return grnfr_online.L(fr, en) end
local function num(x) x = tonumber(x) if x == nil or x ~= x or math.abs(x) > 100000 then return nil end return x end

local function playerVeh() local ok, v = pcall(function() return be:getPlayerVehicle(0) end) if ok then return v end end

local function levelExists(level)
  local ok, r = pcall(function() return FS:directoryExists('/levels/' .. level) end)
  if ok and type(r) == 'boolean' then return r end
  return true -- API absente : on tente quand même le chargement
end

local function loadLevel(level)
  local path = '/levels/' .. level .. '/main.level.json'
  local tries = {
    function() return freeroam_freeroam and freeroam_freeroam.startFreeroamByName and freeroam_freeroam.startFreeroamByName(level, nil, nil) ~= false end,
    function() if freeroam_freeroam and freeroam_freeroam.startFreeroam then freeroam_freeroam.startFreeroam(path) return true end end,
    function() if core_levels and core_levels.startLevel then core_levels.startLevel(path) return true end end,
  }
  for _, f in ipairs(tries) do
    local ok, r = pcall(f)
    if ok and r then return true end
  end
  return false
end

-- Place la voiture du joueur à quelques mètres de pos (jamais pile dessus : l'autre joueur y est déjà).
local function placeNear(pos)
  local v = playerVeh()
  if not v or not pos then return false end
  local x, y, z = num(pos.x), num(pos.y), num(pos.z)
  if not x or not y or not z then return false end
  local p = vec3(x + 6, y + 6, z + 1)
  local ok = pcall(function()
    if spawn and spawn.safeTeleport then spawn.safeTeleport(v, p, quat(0, 0, 0, 1))
    else v:setPositionRotation(p.x, p.y, p.z, 0, 0, 0, 1) end
  end)
  if not ok then slog('warn', 'Travel: the game refused to move the player next to the others.') end
  return ok
end

-- level = nom de dossier de carte (ex. west_coast_usa) ; pos = {x,y,z} d'un joueur déjà présent, ou nil.
-- level absent (serveur vide) : on reste sur la carte actuelle, ou depuis le menu principal on charge DEFAULT_LEVEL.
local DEFAULT_LEVEL = 'west_coast_usa'
function M.go(level, pos)
  if level == nil then
    if grnfr_places.level() ~= 'unknown' then return true end
    level, pos = DEFAULT_LEVEL, nil
  end
  if type(level) ~= 'string' or not level:match('^[%w_%-]+$') or #level > 60 then return false end
  if type(pos) ~= 'table' then pos = nil end
  if grnfr_places.level() == level then
    target = nil
    if pos then placeNear(pos) end
    return true
  end
  if not levelExists(level) then
    slog('warn', 'Travel: the server map is not installed (' .. level .. ').')
    grnfr_online.toast(L('Carte du serveur absente : ', 'Server map not installed: ') .. level, 'error')
    return false
  end
  slog('info', 'Travel: loading the server map (' .. level .. ').')
  grnfr_online.toast(L('Chargement de la carte du serveur : ', 'Loading the server map: ') .. level)
  target, waitAcc = { level = level, pos = pos }, 0
  if not loadLevel(level) then
    target = nil
    slog('warn', 'Travel: the game refused to load the map.')
    grnfr_online.toast(L('Impossible de charger la carte ', 'Could not load the map ') .. level, 'error')
    return false
  end
  return true
end

function M.cancel() target = nil end

function M.update(dt)
  if not target then return end
  waitAcc = waitAcc + dt
  if waitAcc > WAIT_MAX then target = nil; slog('warn', 'Travel: gave up waiting for the server map.') return end
  if grnfr_places.level() ~= target.level or not playerVeh() then return end
  target.settle = (target.settle or 0) + dt
  if target.settle < SETTLE then return end
  local pos = target.pos
  target = nil
  if pos then placeNear(pos) end
  slog('info', 'Travel: arrived on the server map.')
end

return M
