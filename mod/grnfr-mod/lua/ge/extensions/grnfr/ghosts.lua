-- GRNFR Online : voir les autres joueurs du serveur de jeu (4 maximum) avec leur pseudo.
--
-- Principe : BeamNG n'a pas de multijoueur intégré. Sans BeamMP, chaque joueur envoie la position de son véhicule
-- (ou de son personnage à pied, « unicycle ») à Supabase ~3 fois par seconde et reçoit celles des autres.
-- Ce module fait apparaître chez chacun un véhicule « fantôme » par joueur distant, le déplace en lissant / en
-- extrapolant avec la vitesse reçue, et écrit le pseudo au-dessus. Ce n'est PAS de la physique partagée :
-- les fantômes ne décident de rien (argent, courses, garage restent côté serveur).
-- Le transport HTTP est fait par l'interface (net.js) : ce module reçoit les données via onSync(json)
-- et envoie sa propre position à l'interface via l'événement GRNFRSelf.
-- Toutes les API du jeu sont sous pcall (non vérifiées en jeu).
local M = {}

local joined, serverName, interval = false, nil, 0.3
local remote = {}        -- pseudo -> { d = dernières données, t = heure de réception, obj = id, key = 'modèle|config', pos = vec3 lissé }
local selfAcc, clock = 0, 0
local lastSpawn = {}     -- pseudo -> heure du dernier essai d'apparition (évite de boucler si le jeu refuse)
local MAX_GHOSTS = 7
local NAME_RANGE = 400   -- m : au-delà, pas de pseudo affiché
local MAX_EXTRAPOLATE = 1.0 -- s

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local function num(x, d) x = tonumber(x) if x ~= x or x == nil then return d end return x end

local function playerVeh() local ok, v = pcall(function() return be:getPlayerVehicle(0) end) if ok then return v end end

local function deleteObj(id)
  pcall(function() local o = be:getObjectByID(id) if o then o:delete() end end)
end

local function despawn(name)
  local r = remote[name]
  if r and r.obj then deleteObj(r.obj) end
  remote[name] = nil
end

-- ------------------------------------------------------------------ mon propre état (envoyé au serveur)
local function configKey(v)
  local ok, pc = pcall(function() return v.partConfig end)
  if ok and type(pc) == 'string' then return pc:match('([^/\\]+)%.pc$') end
end

-- { level, pos{x,y,z}, rot{x,y,z,w}, vel{x,y,z}, veh{model,config} } ou nil
function M.localState()
  local v = playerVeh()
  if not v then return nil end
  local ok, st = pcall(function()
    local p, vel = v:getPosition(), v:getVelocity()
    local q = v:getRotation()
    local s = {
      level = grnfr_places.level(),
      pos = { x = p.x, y = p.y, z = p.z },
      vel = { vel.x, vel.y, vel.z },
      rot = { q.x, q.y, q.z, q.w },
      veh = { model = tostring(v.jbeam or ''), config = configKey(v) },
    }
    return s
  end)
  if ok then return st end
end

-- ------------------------------------------------------------------ réglages venant de l'interface
-- joined=true : on envoie / reçoit la position. name = nom du serveur. intervalMs = cadence d'envoi.
function M.setServer(isJoined, name, intervalMs)
  isJoined = isJoined == true
  if isJoined ~= joined then slog('info', isJoined and 'Online: joined a game server.' or 'Online: left the game server.') end
  joined, serverName = isJoined, name
  interval = math.max(0.15, (tonumber(intervalMs) or 300) / 1000)
  if not joined then M.reset() end
  return true
end

function M.isGhost(id)
  for _, r in pairs(remote) do if r.obj == id then return true end end
  return false
end

-- ------------------------------------------------------------------ réception : liste des autres joueurs
-- payload = JSON { players = [ { username, level, pos{x,y,z}, rot[4], vel[3], veh{model,config} } ] }
function M.onSync(payload)
  if not joined then return true end
  local ok, d = pcall(jsonDecode, payload or '{}')
  if not ok or type(d) ~= 'table' or type(d.players) ~= 'table' then return true end
  local seen = {}
  for _, p in ipairs(d.players) do
    if type(p) == 'table' and type(p.username) == 'string' and type(p.pos) == 'table' then
      seen[p.username] = true
      local r = remote[p.username]
      if not r then r = { obj = nil }; remote[p.username] = r end
      r.d, r.t = p, clock
    end
  end
  for name in pairs(remote) do if not seen[name] then despawn(name) end end -- le joueur est parti
  pcall(grnfr_track.onPlayers, d.players)
  return true
end

-- ------------------------------------------------------------------ apparition / mise à jour des fantômes
local function ensureGhost(name, r)
  local veh = r.d.veh
  local model = veh and veh.model
  if type(model) ~= 'string' or model == '' then return end
  local key = model .. '|' .. tostring(veh.config or '')
  if r.obj and r.key == key then
    local ok, o = pcall(function() return be:getObjectByID(r.obj) end)
    if ok and o then return o end
    r.obj = nil -- le jeu l'a supprimé (changement de carte, rangement...)
  end
  if r.obj and r.key ~= key then deleteObj(r.obj); r.obj = nil end -- il a changé de véhicule
  if (lastSpawn[name] or -99) + 3 > clock then return end
  lastSpawn[name] = clock
  local count = 0
  for _, x in pairs(remote) do if x.obj then count = count + 1 end end
  if count >= MAX_GHOSTS then return end
  local ok, obj = pcall(function()
    local opts = { autoEnterVehicle = false, vehicleName = 'grnfr_ghost_' .. name }
    if veh.config and veh.config ~= '' then opts.config = veh.config end
    opts.pos = vec3(num(r.d.pos.x, 0), num(r.d.pos.y, 0), num(r.d.pos.z, 0) + 0.3)
    if type(r.d.rot) == 'table' and #r.d.rot == 4 then opts.rot = quat(r.d.rot[1], r.d.rot[2], r.d.rot[3], r.d.rot[4]) end
    return core_vehicles.spawnNewVehicle(model, opts)
  end)
  if not ok or not obj then
    slog('warn', 'Ghosts: the game refused to spawn the model of another player.')
    return
  end
  local id = type(obj) == 'number' and obj or obj:getID()
  r.obj, r.key, r.pos = id, key, nil
  -- Sans collision avec les vraies voitures (méthodes non vérifiées : on essaie les deux noms connus).
  pcall(function()
    local o = be:getObjectByID(id)
    o:queueLuaCommand('if obj.setGhostEnabled then obj:setGhostEnabled(true) end')
  end)
  return be:getObjectByID(id)
end

local function drawName(p, name, dist)
  pcall(function()
    local pos = vec3(p.x, p.y, p.z + 2.2)
    if debugDrawer.drawTextAdvanced then
      debugDrawer:drawTextAdvanced(pos, String(name), ColorF(1, 1, 1, 1), true, false, ColorI(0, 0, 0, 170))
    else
      debugDrawer:drawText(pos, String(name), ColorF(1, 1, 1, 1))
    end
  end)
end

function M.update(dt)
  clock = clock + dt
  if not joined then return end
  -- envoi de mon état à l'interface (qui appelle le serveur)
  selfAcc = selfAcc + dt
  if selfAcc >= interval then
    selfAcc = 0
    local st = M.localState()
    if st then guihooks.trigger('GRNFRSelf', st) end
  end
  local me = playerVeh()
  local myLevel = grnfr_places.level()
  for name, r in pairs(remote) do
    local d = r.d
    if d and d.level == myLevel then
      local o = ensureGhost(name, r)
      if o then
        local age = math.min(MAX_EXTRAPOLATE, clock - r.t)
        local vel = type(d.vel) == 'table' and d.vel or { 0, 0, 0 }
        local tx = num(d.pos.x, 0) + num(vel[1], 0) * age
        local ty = num(d.pos.y, 0) + num(vel[2], 0) * age
        local tz = num(d.pos.z, 0) + num(vel[3], 0) * age
        local target = vec3(tx, ty, tz)
        local cur = r.pos
        -- téléportation si trop loin, sinon lissage
        if not cur or (cur - target):length() > 30 then cur = target
        else
          local k = math.min(1, dt * 12)
          cur = cur + (target - cur) * k
        end
        r.pos = cur
        local rot = type(d.rot) == 'table' and d.rot or { 0, 0, 0, 1 }
        pcall(function() o:setPositionRotation(cur.x, cur.y, cur.z, num(rot[1], 0), num(rot[2], 0), num(rot[3], 0), num(rot[4], 1)) end)
        local dist = me and (me:getPosition() - cur):length() or 0
        if dist <= NAME_RANGE then drawName(cur, name, dist) end
      end
    elseif r.obj then
      deleteObj(r.obj); r.obj = nil -- sur une autre carte : pas de fantôme ici
    end
  end
end

-- État pour l'interface.
function M.status()
  local list = {}
  for name, r in pairs(remote) do
    list[#list + 1] = { username = name, level = r.d and r.d.level, shown = r.obj ~= nil }
  end
  table.sort(list, function(a, b) return a.username < b.username end)
  return { joined = joined, server = serverName, players = list }
end

function M.reset()
  for name in pairs(remote) do despawn(name) end
  remote, lastSpawn, selfAcc = {}, {}, 0
end

return M
