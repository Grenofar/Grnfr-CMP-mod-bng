-- GRNFR Online : en rejoignant un serveur, on arrive sur la carte des autres joueurs, devant son garage.
--
-- L'interface (net.js) demande au serveur où sont les joueurs déjà présents, puis appelle go(level, pos) :
--   * autre carte (ou menu principal) : on démarre cette carte en JEU LIBRE, comme le menu « Jouer » du jeu
--     (freeroam_freeroam.startFreeroam, chargé à la demande s'il ne l'est pas encore) : le jeu sait alors qu'on
--     est en partie (état « freeroam », interface de jeu, véhicule du joueur) au lieu de rester sur le menu ;
--   * même carte : pas de rechargement.
-- Puis, une fois la carte prête : la voiture est placée près du joueur déjà présent (pour que le garage soit
-- attribué de ce côté de la carte), le garage est attribué (garage.lua), et la voiture est posée devant SON
-- garage, à portée de la tablette. Ça se fait à chaque arrivée sur un serveur.
-- Les API de chargement / téléportation sont des hypothèses non vérifiées en jeu (copiées sur le multijoueur
-- BeamMP, qui démarre ses cartes de la même façon) : tout est sous pcall, avec des solutions de repli.
local M = {}

local target = nil      -- { level, pos, phase = 'load' | 'host' | 'garage', t, settle, loadedByUs }
local WAIT_LOAD = 90    -- s : carte jamais chargée / véhicule jamais apparu -> on abandonne
local WAIT_GARAGE = 20  -- s : garage jamais attribué -> on reste où on est
local SETTLE = 2        -- s : après l'apparition du véhicule, on laisse la carte finir de se poser
local DEFAULT_LEVEL = 'west_coast_usa'

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local function L(fr, en) return grnfr_online.L(fr, en) end
local function num(x) x = tonumber(x) if x == nil or x ~= x or math.abs(x) > 100000 then return nil end return x end

local function playerVeh() local ok, v = pcall(function() return be:getPlayerVehicle(0) end) if ok then return v end end

-- Entrée de la liste des cartes du jeu (table avec levelName, misFilePath...), comme celle du menu « Jouer ».
local function levelEntry(level)
  local ok, e = pcall(function()
    for _, v in ipairs(core_levels.getList()) do
      if v.levelName and tostring(v.levelName):lower() == level:lower() then return v end
    end
  end)
  if ok then return e end
end

local function levelExists(level)
  if levelEntry(level) then return true end
  local ok, r = pcall(function() return FS:directoryExists('/levels/' .. level) end)
  if ok and type(r) == 'boolean' then return r end
  return true -- API absente : on tente quand même le chargement
end

local function gameState()
  local ok, s = pcall(function() return core_gamestate.state.state end)
  if ok and type(s) == 'string' then return s end
end

-- Démarre la carte en jeu libre. Renvoie true si le jeu a accepté.
local function loadLevel(level)
  local entry = levelEntry(level)
  local path = (entry and entry.misFilePath) or ('/levels/' .. level .. '/')
  -- le module « jeu libre » n'est pas forcément chargé depuis le menu principal : on le charge
  pcall(function() if not rawget(_G, 'freeroam_freeroam') then extensions.load('freeroam_freeroam') end end)
  local tries = {
    function() if freeroam_freeroam and freeroam_freeroam.startFreeroam then freeroam_freeroam.startFreeroam(entry or path) return true end end,
    function() if freeroam_freeroam and freeroam_freeroam.startFreeroamByName then return freeroam_freeroam.startFreeroamByName(level) == true end end,
    function() if core_levels and core_levels.startLevel then core_levels.startLevel(path) return true end end,
  }
  for i, f in ipairs(tries) do
    local ok, r = pcall(f)
    if ok and r then slog('info', 'Travel: map start method #' .. i .. ' accepted.') return true end
  end
  return false
end

-- Place la voiture du joueur à `away` mètres de pos.
local function placeNear(pos, away)
  local v = playerVeh()
  if not v or type(pos) ~= 'table' then return false end
  local x, y, z = num(pos.x), num(pos.y), num(pos.z)
  if not x or not y or not z then return false end
  local d = (away or 6) / math.sqrt(2)
  local p = vec3(x + d, y + d, z + 1)
  local ok = pcall(function()
    if spawn and spawn.safeTeleport then spawn.safeTeleport(v, p, quat(0, 0, 0, 1))
    else v:setPositionRotation(p.x, p.y, p.z, 0, 0, 0, 1) end
  end)
  if not ok then slog('warn', 'Travel: the game refused to move the player car.') end
  return ok
end

local function hold(on) pcall(grnfr_garage.setHold, on) end

-- level = nom de dossier de carte (ex. west_coast_usa) ; pos = {x,y,z} d'un joueur déjà présent, ou nil.
-- level absent (serveur vide) : on reste sur la carte actuelle, ou depuis le menu principal on charge DEFAULT_LEVEL.
-- beforeLoad (facultatif) : appelé juste avant de lancer le chargement d'une carte (fermer les fenêtres du mod).
-- resume (0020, reconnexion à un serveur où l'on était déjà) : pos est alors MA dernière position connue, pas
-- celle d'un autre joueur -> une fois arrivé là, on ne force PLUS le trajet jusqu'au garage (M.update) : le
-- joueur reste où il était (dans la voiture par défaut du jeu libre), libre d'aller chercher la sienne quand il
-- veut (téléphone, touche K > « Aller à mon garage »). Le garage continue d'être attribué en arrière-plan (hold(false)).
function M.go(level, pos, beforeLoad, resume)
  resume = resume == true
  local cur = grnfr_places.level()
  if level == nil then
    if cur ~= 'unknown' then level = cur else level = DEFAULT_LEVEL end
    pos = nil
  end
  if type(level) ~= 'string' or not level:match('^[%w_%-]+$') or #level > 60 then hold(false) return false end
  if type(pos) ~= 'table' then pos = nil end
  if cur == level then
    target = { level = level, pos = pos, phase = 'host', t = 0, settle = SETTLE, resume = resume }
    return true
  end
  if not levelExists(level) then
    hold(false)
    slog('warn', 'Travel: the server map is not installed (' .. level .. ').')
    grnfr_online.toast(L('Carte du serveur absente : ', 'Server map not installed: ') .. level, 'error')
    return false
  end
  slog('info', 'Travel: loading the server map (' .. level .. ').')
  grnfr_online.toast(L('Chargement de la carte du serveur : ', 'Loading the server map: ') .. level)
  target = { level = level, pos = pos, phase = 'load', t = 0, settle = 0, loadedByUs = true, resume = resume }
  if beforeLoad then pcall(beforeLoad) end
  if not loadLevel(level) then
    target = nil
    hold(false)
    slog('warn', 'Travel: the game refused to load the map.')
    grnfr_online.toast(L('Impossible de charger la carte ', 'Could not load the map ') .. level, 'error')
    return false
  end
  return true
end

function M.cancel() target = nil end
function M.active() return target ~= nil end

function M.update(dt)
  if not target then return end
  target.t = target.t + dt
  if target.phase == 'load' or target.phase == 'host' then
    if target.t > WAIT_LOAD then target = nil; hold(false); slog('warn', 'Travel: gave up waiting for the server map.') return end
    if grnfr_places.level() ~= target.level or not playerVeh() then target.settle = 0 return end
    target.settle = target.settle + dt
    if target.settle < SETTLE then return end
    -- repli : carte chargée sans le mode jeu libre -> on dit au jeu qu'on est en partie (interface de jeu)
    if target.loadedByUs then
      local gs = gameState()
      if gs ~= 'freeroam' and gs ~= 'multiplayer' then
        pcall(function() core_gamestate.setGameState('freeroam', 'freeroam', 'freeroam') end)
        slog('info', 'Travel: set the game state to free roam (was ' .. tostring(gs) .. ').')
      end
    end
    if target.pos then placeNear(target.pos, 8) end
    hold(false) -- le garage peut maintenant être attribué, depuis cette position
    if target.resume then
      slog('info', 'Travel: resumed at the last known position, no forced trip to the garage.')
      target = nil
      return
    end
    target.phase, target.t = 'garage', 0
    return
  end
  if target.phase == 'garage' then
    local mine = grnfr_garage.mine and grnfr_garage.mine()
    if mine and type(mine.pos) == 'table' then
      target = nil
      if mine.garage then
        if not grnfr_garage.teleportHome(playerVeh()) then
          grnfr_online.toast(L('Impossible de vous placer au garage : téléphone (touche K) > « Aller à mon garage ».', 'Could not place you at your garage: phone (K key) > "Go to my garage".'), 'warning')
        end
        slog('info', 'Travel: at the garage, asking the interface which vehicle to take out.')
        -- l'interface connaît mes véhicules : elle répond par server.arrive (voir M.arrive)
        guihooks.trigger('GRNFRArrived', { garage = mine.garage.name })
      else
        slog('info', 'Travel: your garage on this server is on another map, staying here.')
      end
    elseif target.t > WAIT_GARAGE then
      target = nil
      slog('warn', 'Travel: no garage was given in time, staying here.')
    end
  end
end

-- Arrivée au garage, comme la carrière : dans SA voiture (sortie sur une place du garage), ou à pied devant la
-- tablette si on n'en a pas encore (première fois : on va acheter une voiture sur la tablette). La voiture « gratuite »
-- du jeu libre est retirée. v = véhicule du garage à sortir, ou nil.
function M.arrive(v)
  local old = playerVeh()
  local oldId = old and old:getID()
  local function dropOld()
    if not oldId then return end
    for _, s in pairs(grnfr_online.spawnedList()) do if s.obj == oldId then return end end
    if grnfr_ghosts.isGhost(oldId) then return end
    pcall(function() local o = be:getObjectByID(oldId) if o then o:delete() end end)
  end
  if type(v) == 'table' and v.model_key then
    if grnfr_online.spawnVehicle(v, true) then
      dropOld()
      grnfr_online.toast(L('Bienvenue ! Votre véhicule vous attend au garage. Ordinateur : touche O. Téléphone : touche K.',
        'Welcome! Your vehicle is at your garage. Computer: O key. Phone: K key.'))
      return true
    end
  end
  -- à pied devant la tablette (API de la carrière, non vérifiées : gameplay_walk.setWalkingMode, spawn.safeTeleport)
  local mine = grnfr_garage.mine()
  local ok = pcall(function()
    gameplay_walk.setWalkingMode(true)
    if mine and mine.pos then
      local t = vec3(mine.pos.x, mine.pos.y, mine.pos.z)
      spawn.safeTeleport(be:getPlayerVehicle(0), t + vec3(1.5, 1.5, 0.3))
      pcall(function() gameplay_walk.setRot(t - be:getPlayerVehicle(0):getPosition(), vec3(0, 0, 1)) end)
    end
  end)
  if ok then dropOld() else slog('warn', 'Travel: could not switch to walking mode.') end
  grnfr_online.toast(L('Vous êtes à pied devant votre garage : achetez votre première voiture sur l\'ordinateur (touche O). Téléphone : touche K.',
    'You are on foot at your garage: buy your first car on the computer (O key). Phone: K key.'))
  return true
end

return M
