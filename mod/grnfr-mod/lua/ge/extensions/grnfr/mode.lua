-- Détection du mode de jeu. Chaque détecteur est protégé par pcall : une API absente ne casse rien.
-- Résultat : { id = principal, ids = liste (ex. {'career','bus'}), raw = nom brut si inconnu, session = bool }.
-- Les noms d'API (gameplay_garageMode, gameplay_missions_missionManager, MPCoreNetwork...) sont des
-- hypothèses non vérifiées en jeu : si l'une est absente, le mode retombe sur l'état brut du jeu.
local M = {}

local function try(fn)
  local ok, r = pcall(fn)
  if ok then return r end
end

local function levelLoaded()
  if not getMissionFilename then return false end
  local ok, name = pcall(getMissionFilename)
  return ok and type(name) == 'string' and name ~= ''
end

local function gameState()
  local s = try(function() return core_gamestate.state.state end)
  return type(s) == 'string' and s or nil
end

local function careerActive()
  return try(function() return career_career and career_career.isActive and career_career.isActive() end) == true
end

local function garageActive()
  return try(function() return gameplay_garageMode and gameplay_garageMode.isActive and gameplay_garageMode.isActive() end) == true
end

local function missionType()
  local t = try(function()
    local mm = gameplay_missions_missionManager
    local m = mm and mm.getRunningMission and mm.getRunningMission()
    if not m then return nil end
    return m.missionType or (m.getMissionType and m:getMissionType()) or m.id
  end)
  if t ~= nil then return tostring(t) end
end

local function onlineMultiplayer()
  return try(function()
    if not MPCoreNetwork then return false end
    if MPCoreNetwork.isMPSession then return MPCoreNetwork.isMPSession() == true end
    return false
  end) == true
end

local function localMultiplayer()
  -- un 2e joueur local possède un véhicule à l'index 1 (non vérifié)
  -- on ignore l'index 1 s'il renvoie le même véhicule que l'index 0 (faux positif en solo)
  local id = try(function() return be:getPlayerVehicleID(1) end)
  local id0 = try(function() return be:getPlayerVehicleID(0) end)
  return type(id) == 'number' and id >= 0 and id ~= id0
end

function M.detect()
  if not levelLoaded() then
    return { id = 'menu', ids = { 'menu' }, label = 'Menu principal', session = false }
  end
  local ids, raw = {}, nil
  local function add(id) ids[#ids + 1] = id end
  local gs = gameState()
  local gsl = gs and gs:lower() or ''

  if careerActive() then add('career') end
  if garageActive() or gsl == 'garage' then add('garage') end

  local mt = missionType()
  if mt then
    local l = mt:lower()
    if l:find('bus') then add('bus')
    elseif l:find('rally') then add('rally')
    else add('mission'); raw = mt end
  end

  if gsl:find('experience') then add('startexp') end
  if onlineMultiplayer() then add('multiplayer') elseif localMultiplayer() then add('localmp') end

  -- Jeu libre : reconnu même si un autre détecteur a répondu (multijoueur local, expérience de démarrage...),
  -- tant qu'aucun mode exclusif (carrière, mission, bus, rallye, garage) n'est actif.
  local exclusive = false
  for _, id in ipairs(ids) do
    if id == 'career' or id == 'mission' or id == 'bus' or id == 'rally' or id == 'garage' then exclusive = true end
  end
  if gsl == 'freeroam' and not exclusive then table.insert(ids, 1, 'freeroam') end

  if #ids == 0 then
    if gsl == 'freeroam' then add('freeroam')
    elseif gsl == 'scenario' then add('scenario')
    elseif gs and gs ~= '' and gsl ~= 'menu' then add('raw'); raw = gs -- état inconnu : on affiche son nom brut
    else add('session') end
  end
  -- diag : valeurs brutes des détecteurs, affichées dans l'onglet Gameplay pour comprendre une détection ratée
  local diag = string.format('gamestate=%s career=%s garage=%s mission=%s mp=%s localmp=%s',
    tostring(gs), tostring(careerActive()), tostring(garageActive()), tostring(mt), tostring(onlineMultiplayer()), tostring(localMultiplayer()))
  return { id = ids[1], ids = ids, raw = raw, label = 'Session active (mode inconnu)', session = true, diag = diag }
end

return M
