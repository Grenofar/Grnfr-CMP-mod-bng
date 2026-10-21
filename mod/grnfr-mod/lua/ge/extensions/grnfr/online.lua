-- GRNFR Online : pont jeu <-> Supabase.
--
-- Le jeu (Lua) ne sait pas faire de HTTPS. C'est l'interface (ui/ui-vue/mods/GRNFR/net.js) qui parle à Supabase et qui
-- garde le jeton de connexion. Ce module :
--   * envoie à l'interface les demandes réseau du jeu (événement GRNFRNetReq) et reçoit les réponses (onNetResult) ;
--   * envoie périodiquement la position du joueur (événement GRNFRPos) pour la présence / le taxi ;
--   * fait apparaître / range les véhicules du garage dans le monde ;
--   * pousse l'état « jeu » (taxi, bus, destination) à l'interface (événement GRNFROnline).
-- Aucune règle d'argent ici : tout est décidé et vérifié par le serveur (voir supabase/migrations).
local M = {}

local nextId, pending = 0, {}
local authed, username = false, nil
local posAcc, stateAcc, lastSig = 0, 0, ''
local spawned = {} -- id du véhicule du garage -> id de l'objet dans le jeu
local TIMEOUT = 25

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local function lang() local ok, l = pcall(function() return grnfr_settings.get().lang end) return ok and l or 'fr' end
function M.L(fr, en) return lang() == 'en' and en or fr end

function M.toast(msg, kind)
  pcall(function() guihooks.trigger('toastrMsg', { type = kind or 'info', title = 'GRNFR Online', msg = msg, config = { timeOut = 6000 } }) end)
end

function M.isAuthed() return authed end
function M.username() return username end

-- Appel d'une fonction RPC du serveur. cb(ok, data) : data = valeur retournée (ok) ou code d'erreur texte (échec).
function M.call(fn, args, cb)
  if not authed then if cb then cb(false, 'not_authenticated') end return end
  nextId = nextId + 1
  pending[nextId] = { cb = cb, t = 0, fn = fn }
  guihooks.trigger('GRNFRNetReq', { id = nextId, fn = fn, args = args or {} })
end

-- Réponse de l'interface. payload = JSON {"r": résultat} ou {"e": "code_erreur"}.
function M.onNetResult(id, ok, payload)
  local p = pending[id]
  if not p then return true end
  pending[id] = nil
  local data
  local okd, d = pcall(jsonDecode, payload or '{}')
  if okd and type(d) == 'table' then
    if ok == true then data = d.r else data = d.e or 'error' end
  elseif ok ~= true then data = 'error' end
  if p.cb then
    local okc, err = pcall(p.cb, ok == true, data)
    if not okc then slog('problem', 'Online callback failed for ' .. tostring(p.fn) .. '.') end
  end
  return true
end

-- Message lisible pour un code d'erreur du serveur.
local ERR = {
  insufficient_funds = { 'Fonds insuffisants.', 'Not enough money.' },
  too_far = { 'Vous êtes trop loin du point.', 'You are too far from the spot.' },
  too_fast = { 'Trajet trop rapide pour être crédible.', 'Trip too fast to be believable.' },
  job_unavailable = { 'Mission expirée ou déjà terminée.', 'Job expired or already finished.' },
  request_unavailable = { 'Course indisponible.', 'Ride unavailable.' },
  not_authenticated = { 'Connectez-vous d\'abord (touche O).', 'Sign in first (O key).' },
  timeout = { 'Le serveur ne répond pas.', 'The server is not answering.' },
  already_active = { 'Une course est déjà en cours.', 'A ride is already in progress.' },
  too_short = { 'Trajet trop court.', 'Trip too short.' },
  too_long = { 'Trajet trop long.', 'Trip too long.' },
  not_in_server = { 'Vous n\'êtes plus dans le serveur.', 'You are no longer in the server.' },
  garage_full = { 'Plus de place de garage sur ce serveur.', 'No garage spot left on this server.' },
  bad_position = { 'Position invalide.', 'Invalid position.' },
  bad_message = { 'Message vide ou trop long.', 'Empty or too long message.' },
  race_active = { 'Une course de drag est déjà en cours sur ce serveur.', 'A drag race is already active on this server.' },
  betting_closed = { 'Les mises sont closes pour cette course.', 'Betting is closed for this race.' },
  already_in = { 'Vous êtes déjà dans cette course.', 'You are already in this race.' },
  bad_stake = { 'Mise invalide.', 'Invalid stake.' },
  race_not_found = { 'Course introuvable.', 'Race not found.' },
  not_entered = { 'Vous n\'êtes pas inscrit à cette course.', 'You are not entered in this race.' },
  already_finished = { 'Temps déjà enregistré.', 'Time already recorded.' },
  bad_time = { 'Temps invalide.', 'Invalid time.' },
  race_not_running = { 'La course n\'est pas en cours.', 'The race is not running.' },
  not_enough_players = { 'Pas assez de joueurs inscrits (2 minimum).', 'Not enough entrants (2 minimum).' },
  forbidden = { 'Réservé à l\'hôte de la course.', 'Host only.' },
}
function M.errText(code)
  local e = ERR[tostring(code)]
  if e then return M.L(e[1], e[2]) end
  return M.L('Erreur serveur : ', 'Server error: ') .. tostring(code)
end

-- L'interface annonce la connexion / déconnexion du joueur.
function M.setAuth(loggedIn, name)
  authed, username = loggedIn == true, name
  slog('info', authed and 'Online: signed in.' or 'Online: signed out.')
  if not authed then pending = {} end
  lastSig = ''
end

-- ------------------------------------------------------------------ garage : véhicules dans le monde
local function playerVeh() local ok, v = pcall(function() return be:getPlayerVehicle(0) end) if ok then return v end end

local function deleteObj(id)
  pcall(function() local o = be:getObjectByID(id) if o then o:delete() end end)
end

-- v = { id, model_key, config_key, nickname }
function M.spawnVehicle(v)
  if type(v) ~= 'table' or not v.model_key then return false end
  if spawned[v.id] then deleteObj(spawned[v.id]); spawned[v.id] = nil end
  local pv = playerVeh()
  local ok, obj = pcall(function()
    local opts = { autoEnterVehicle = true }
    if v.config_key and v.config_key ~= '' then opts.config = v.config_key end
    if pv then
      local pos, dir, up = pv:getPosition(), pv:getDirectionVector(), pv:getDirectionVectorUp()
      local right = dir:cross(up):normalized()
      opts.pos = pos + right * 4 + dir * 2
      opts.rot = quatFromDir(dir, up)
    end
    return core_vehicles.spawnNewVehicle(v.model_key, opts)
  end)
  if not ok or not obj then
    slog('warn', 'Garage: the game refused to spawn a vehicle.')
    M.toast(M.L('Impossible de faire apparaître ce véhicule.', 'Could not spawn this vehicle.'), 'error')
    return false
  end
  spawned[v.id] = type(obj) == 'number' and obj or obj:getID()
  lastSig = ''
  return true
end

function M.storeVehicle(id)
  if spawned[id] then deleteObj(spawned[id]); spawned[id] = nil; lastSig = '' end
  return true
end

-- ------------------------------------------------------------------ saisie clavier dans l'interface
-- Pendant qu'un champ texte est actif, les touches ne doivent pas piloter la voiture (API non vérifiée).
function M.setTyping(on)
  pcall(function() if setCEFTyping then setCEFTyping(on == true) end end)
  return true
end
function M.setFocus(on)
  pcall(function() if setCEFFocus then setCEFFocus(on == true) end end)
  return true
end

-- ------------------------------------------------------------------ état poussé à l'interface
local function status(name)
  local m = rawget(_G, name)
  if m and m.status then
    local ok, s = pcall(m.status)
    if ok then return s end
  end
end

local function buildState()
  local sp = {}
  for id, objId in pairs(spawned) do
    local ok, o = pcall(function() return be:getObjectByID(objId) end)
    if ok and o then sp[id] = true else spawned[id] = nil end
  end
  local pos = grnfr_places.playerPos()
  return {
    authed = authed,
    level = grnfr_places.level(),
    pos = pos and { x = pos.x, y = pos.y, z = pos.z } or nil,
    spawned = sp,
    taxi = status('grnfr_taxi'),
    bot = status('grnfr_taxibot'),
    bus = status('grnfr_bus'),
    garage = status('grnfr_garage'),
    chat = status('grnfr_chat'),
    drag = status('grnfr_drag'),
    track = status('grnfr_track'),
    nav = (function()
      local t = grnfr_nav.get()
      if not t then return nil end
      return { label = t.label, dist = math.floor(grnfr_nav.distance() or 0) }
    end)(),
  }
end

function M.pushState(force)
  local st = buildState()
  local ok, sig = pcall(jsonEncode, st)
  if not ok then return end
  if force or sig ~= lastSig then lastSig = sig; guihooks.trigger('GRNFROnline', st) end
end

function M.update(dt)
  for id, p in pairs(pending) do
    p.t = p.t + dt
    if p.t > TIMEOUT then
      pending[id] = nil
      if p.cb then pcall(p.cb, false, 'timeout') end
    end
  end
  posAcc, stateAcc = posAcc + dt, stateAcc + dt
  if authed and posAcc >= 5 then
    posAcc = 0
    local pos = grnfr_places.playerPos()
    local duty = 'none'
    local t, b = status('grnfr_taxi'), status('grnfr_bus')
    if t and t.duty then duty = 'taxi' elseif b and b.active then duty = 'bus' end
    guihooks.trigger('GRNFRPos', { level = grnfr_places.level(), pos = pos and { x = pos.x, y = pos.y, z = pos.z } or nil, duty = duty })
  end
  if stateAcc >= 0.5 then stateAcc = 0; M.pushState(false) end
end

-- Liste de destinations (lieux nommés ou points de route) envoyée à l'interface.
function M.requestPlaces()
  local list = grnfr_places.list(nil, 8)
  guihooks.trigger('GRNFRPlaces', { places = list })
  return true
end

function M.reset()
  for _, objId in pairs(spawned) do deleteObj(objId) end
  spawned, pending = {}, {}
  lastSig = ''
end

return M
