-- Simulation hors jeu : fausse API BeamNG + faux serveur, pour dérouler taxi PNJ, bus et taxi IA de bout en bout.
-- Usage : texlua tests/lua_sim.lua   (depuis la racine du dépôt)
math.randomseed(42)
local ROOT = 'mod/grnfr-mod/lua/ge/extensions/grnfr/'

-- ---------- JSON minimal
local function enc(v)
  local t = type(v)
  if t == 'nil' then return 'null' elseif t == 'boolean' or t == 'number' then return tostring(v)
  elseif t == 'string' then return '"' .. v:gsub('[\\"]', '\\%0') .. '"'
  elseif t == 'table' then
    if #v > 0 or next(v) == nil then local a = {} for _, x in ipairs(v) do a[#a + 1] = enc(x) end return '[' .. table.concat(a, ',') .. ']' end
    local a = {} for k, x in pairs(v) do a[#a + 1] = enc(tostring(k)) .. ':' .. enc(x) end table.sort(a) return '{' .. table.concat(a, ',') .. '}'
  end
end
local function dec(s)
  local i = 1
  local function ws() i = s:find('%S', i) or #s + 1 end
  local val
  function val()
    ws(); local c = s:sub(i, i)
    if c == '{' then local r = {} i = i + 1 ws()
      if s:sub(i, i) == '}' then i = i + 1 return r end
      while true do ws() local k = val() ws() i = i + 1 r[k] = val() ws() local d = s:sub(i, i) i = i + 1 if d == '}' then return r end end
    elseif c == '[' then local r = {} i = i + 1 ws()
      if s:sub(i, i) == ']' then i = i + 1 return r end
      while true do r[#r + 1] = val() ws() local d = s:sub(i, i) i = i + 1 if d == ']' then return r end end
    elseif c == '"' then local j = i + 1 local out = {}
      while s:sub(j, j) ~= '"' do if s:sub(j, j) == '\\' then j = j + 1 end out[#out + 1] = s:sub(j, j) j = j + 1 end
      i = j + 1 return table.concat(out)
    elseif s:sub(i, i + 3) == 'true' then i = i + 4 return true
    elseif s:sub(i, i + 4) == 'false' then i = i + 5 return false
    elseif s:sub(i, i + 3) == 'null' then i = i + 4 return nil
    else local n = s:match('^-?[%d%.eE+-]+', i) i = i + #n return tonumber(n) end
  end
  return val()
end
jsonEncode, jsonDecode = enc, dec

-- ---------- fausse API BeamNG
local V = {}
V.__index = V
V.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, V) end
V.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, V) end
V.__mul = function(a, k) return setmetatable({ x = a.x * k, y = a.y * k, z = a.z * k }, V) end
function V:length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function vec3(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
ColorF = function() return {} end
String = function(s) return s end
debugDrawer = setmetatable({}, { __index = function() return function() end end })
getMissionFilename = function() return '/levels/west_coast_usa/info.json' end

local nodes = {}
for gx = 0, 30 do for gy = 0, 30 do nodes['n' .. gx .. '_' .. gy] = { pos = vec3(gx * 200, gy * 200, 0), radius = 3, links = { a = 1 } } end end
map = {
  getMap = function() return { nodes = nodes } end,
  findClosestRoad = function(p) return 'n' .. math.floor(p.x / 200 + .5) .. '_' .. math.floor(p.y / 200 + .5), nil, 0 end,
  getPath = function(a, b) return { a, b } end,
}

local objects, nextObj = {}, 100
local function mkObj(id, pos) 
  local o = { id = id, pos = pos, vel = 0, cmds = {} }
  function o:getID() return self.id end
  function o:getPosition() return self.pos end
  function o:getVelocity() return vec3(self.vel, 0, 0) end
  function o:getDirectionVector() return vec3(1, 0, 0) end
  function o:getDirectionVectorUp() return vec3(0, 0, 1) end
  function o:queueLuaCommand(c) self.cmds[#self.cmds + 1] = c end
  function o:delete() objects[self.id] = nil end
  function o:setPositionRotation(x, y, z) self.pos = vec3(x, y, z); self.placed = (self.placed or 0) + 1 end
  objects[id] = o
  return o
end
quat = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
ColorI = function() return {} end
local player = mkObj(1, vec3(1000, 1000, 0))
player.jbeam, player.partConfig = 'covet', 'vehicles/covet/base.pc'
function player:getRotation() return quat(0, 0, 0, 1) end
local entered = 1
be = {
  getPlayerVehicle = function() return objects[entered] end,
  getObjectByID = function(_, id) return objects[id] end,
  enterVehicle = function(_, _, o) entered = o.id end,
}
core_vehicles = {
  getConfigList = function() return { configs = { { model_key = 'fullsize', config_key = 'taxi', Name = 'Taxi' } } } end,
  spawnNewVehicle = function(model, opts) nextObj = nextObj + 1 local o = mkObj(nextObj, opts.pos or vec3(0, 0, 0)) o.model, o.name, o.enter = model, opts.vehicleName, opts.autoEnterVehicle return o end,
}
quatFromDir = function() return {} end
guihooks = { events = {}, trigger = function(name, data) guihooks.events[#guihooks.events + 1] = { name, data } end }
local toasts = {}
local log = {}
grnfr_sessionlog = { add = function(k, m) log[#log + 1] = k .. ': ' .. m end }
grnfr_settings = { get = function() return { lang = 'en' } end }
jsonReadFile = function() return nil end
jsonWriteFile = function() return true end

-- ---------- faux serveur (mêmes règles que le SQL, version minuscule)
local jobs, jid = {}, 0
local balance = 1000
local server = {}
function server.start_job(a)
  jid = jid + 1
  local fare = (a.p_kind == 'bus_leg') and 30 or 20
  if a.p_kind == 'bot_taxi' then balance = balance - 30; fare = 30 end
  jobs[jid] = { kind = a.p_kind, status = 'started', fare = fare, pickup = a.p_pickup, dropoff = a.p_dropoff }
  return true, { id = 'job' .. jid, fare = fare, passengers = 3, route_m = a.p_distance_m }
end
local function getJob(id) return jobs[tonumber(id:match('%d+'))] end
local function d(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
function server.board_job(a) local j = getJob(a.p_job) if d(a.p_pos, j.pickup) > 150 then return false, 'too_far' end j.status = 'boarded' return true end
function server.complete_job(a)
  local j = getJob(a.p_job)
  if j.status ~= 'boarded' then return false, 'job_unavailable' end
  if d(a.p_pos, j.dropoff) > 150 then return false, 'too_far' end
  j.status = 'completed'
  if j.kind ~= 'bot_taxi' then balance = balance + j.fare end
  return true, { paid = (j.kind == 'bot_taxi') and 0 or j.fare, capped = false }
end
function server.cancel_job(a) local j = getJob(a.p_job) if j.kind == 'bot_taxi' and j.status == 'started' then balance = balance + j.fare end j.status = 'cancelled' return true end

-- Le pont : les demandes GRNFRNetReq sont traitées immédiatement par le faux serveur.
local online
local function pump()
  local evs = guihooks.events
  guihooks.events = {}
  for _, e in ipairs(evs) do
    if e[1] == 'GRNFRNetReq' then
      local r = e[2]
      local f = server[r.fn]
      local ok, res, extra = true, nil, nil
      if f then ok, res = f(r.args) else ok, res = true, true end
      if ok then online.onNetResult(r.id, true, enc({ r = res })) else online.onNetResult(r.id, false, enc({ e = res })) end
    elseif e[1] == 'toastrMsg' then toasts[#toasts + 1] = e[2].msg end
  end
end

-- ---------- chargement des modules (comme le fait le jeu : une globale par extension)
for _, n in ipairs({ 'places', 'nav', 'online', 'taxi', 'taxibot', 'bus', 'ghosts' }) do _G['grnfr_' .. n] = dofile(ROOT .. n .. '.lua') end
online = grnfr_online

local function step(seconds, dt)
  dt = dt or 0.25
  for _ = 1, math.floor(seconds / dt) do
    grnfr_taxi.update(dt); grnfr_taxibot.update(dt); grnfr_bus.update(dt)
    grnfr_nav.update(); online.update(dt)
    pump()
  end
end
local function teleport(p) player.pos = vec3(p.x, p.y, p.z or 0); player.vel = 0 end
local function check(cond, what) if not cond then print('ECHEC : ' .. what) os.exit(1) end print('ok   ' .. what) end

-- ---------- 1. non connecté : rien ne part
grnfr_taxi.setDuty(true)
check(not grnfr_taxi.status().duty, 'taxi refusé sans connexion')
online.setAuth(true, 'alice')
online.pushState(true)

-- ---------- 2. taxi PNJ complet
check(grnfr_taxi.setDuty(true), 'mise en service')
step(8)
local st = grnfr_taxi.status()
check(st.phase == 'pickup' and st.kind == 'npc', 'passager PNJ généré (phase pickup)')
local t = grnfr_nav.get()
check(t ~= nil, 'balise posée sur le départ')
teleport(t)                                    -- le joueur arrive et s'arrête
step(3)
st = grnfr_taxi.status()
check(st.phase == 'dropoff', 'embarquement validé par le serveur')
t = grnfr_nav.get()
local before = balance
teleport(t)
step(3)
check(balance == before + 20, 'gain versé par le serveur à l\'arrivée (+20)')
check(grnfr_taxi.status().rides == 1, 'compteur de courses')
-- vitesse trop élevée à l'arrivée : pas de validation
step(6)
t = grnfr_nav.get(); check(t ~= nil, 'nouveau passager après la pause')
teleport(t); step(2)
t = grnfr_nav.get(); player.pos = vec3(t.x, t.y, 0); player.vel = 20; step(3)
check(grnfr_taxi.status().phase == 'dropoff', 'pas de paiement tant que le véhicule roule vite')
player.vel = 0; step(3)
check(grnfr_taxi.status().rides == 2, 'paiement dès l\'arrêt')
grnfr_taxi.setDuty(false)
check(grnfr_nav.get() == nil, 'fin de service : balise retirée')

-- ---------- 3. bus
check(grnfr_bus.start(), 'ligne de bus lancée')
local ev0 = grnfr_bus.status()
check(ev0.stops >= 3, 'au moins 3 arrêts : ' .. ev0.stops)
local earned = balance
for stop = 1, 4 do
  t = grnfr_nav.get(); teleport(t); step(6)          -- arrêt + temps d'arrêt + embarquement
  t = grnfr_nav.get(); teleport(t); step(2)          -- arrêt suivant -> paiement
end
check(balance == earned + 4 * 30, 'quatre tronçons payés par le serveur (' .. (balance - earned) .. ')')
check(grnfr_bus.status().legs == 4, 'compteur de tronçons')
grnfr_bus.stop()

-- ---------- 4. taxi IA : appel, arrivée, trajet, paiement
local b0 = balance
check(grnfr_taxibot.call({ x = 3000, y = 1000, z = 0, name = 'Gare' }), 'taxi IA appelé')
step(1)
check(balance == b0 - 30, 'prix réservé (séquestre)')
check(grnfr_taxibot.status().phase == 'wait', 'le taxi arrive')
local taxiObj
for id, o in pairs(objects) do if id > 100 then taxiObj = o end end
check(taxiObj ~= nil and #taxiObj.cmds >= 1 and taxiObj.cmds[1]:find('driveUsingPath'), 'ordre de conduite envoyé au taxi')
taxiObj.pos = vec3(player.pos.x + 5, player.pos.y, 0); taxiObj.vel = 0; step(2)
check(grnfr_taxibot.status().phase == 'ride' and entered == taxiObj.id, 'le joueur est monté dans le taxi')
taxiObj.pos = vec3(3000, 1000, 0); step(2)
check(grnfr_taxibot.status().phase == 'idle' and entered == 1, 'arrivée : joueur rendu à son véhicule')
check(objects[taxiObj.id] == nil, 'taxi supprimé')
-- annulation avant embarquement = remboursement
local b1 = balance
grnfr_taxibot.call({ x = 3000, y = 3000, z = 0 }); step(1); grnfr_taxibot.cancel(); step(1)
check(balance == b1, 'annulation avant embarquement : remboursé')

-- ---------- 5. serveur de jeu : voir les autres joueurs (fantômes + pseudos)
local drawn = {}
debugDrawer = setmetatable({ drawTextAdvanced = function(_, pos, text) drawn[#drawn + 1] = text end }, { __index = function() return function() end end })
local selfEvents = 0
local function lastSelf() local r for _, e in ipairs(guihooks.events) do if e[1] == 'GRNFRSelf' then r = e[2]; selfEvents = selfEvents + 1 end end return r end
teleport({ x = 1000, y = 1000, z = 0 })
check(grnfr_ghosts.setServer(true, 'Serveur 1', 300), 'serveur rejoint')
for _ = 1, 4 do grnfr_ghosts.update(0.1) end
local me = lastSelf()
check(me and me.veh.model == 'covet' and me.veh.config == 'base' and me.pos.x == 1000 and #me.rot == 4 and #me.vel == 3, 'mon état (modèle, config, position, rotation, vitesse) envoyé à l\'interface')
local wc = grnfr_places.level()
local payload = enc({ players = {
  { username = 'bob', level = wc, pos = { x = 1100, y = 1000, z = 0 }, rot = { 0, 0, 0, 1 }, vel = { 10, 0, 0 }, veh = { model = 'etk800', config = 'base' } },
  { username = 'carol', level = wc, pos = { x = 1200, y = 1000, z = 0 }, rot = { 0, 0, 0, 1 }, vel = { 0, 0, 0 }, veh = { model = 'unicycle' } },
  { username = 'dave', level = 'autre_carte', pos = { x = 0, y = 0, z = 0 }, veh = { model = 'covet' } },
} })
grnfr_ghosts.onSync(payload)
for _ = 1, 10 do grnfr_ghosts.update(0.1) end
local ghosts = {}
for id, o in pairs(objects) do if o.name then ghosts[o.name] = o end end
check(ghosts['grnfr_ghost_bob'] and ghosts['grnfr_ghost_bob'].model == 'etk800', 'fantôme de bob (etk800) créé')
check(ghosts['grnfr_ghost_carol'] and ghosts['grnfr_ghost_carol'].model == 'unicycle', 'carol à pied (unicycle) créée')
check(ghosts['grnfr_ghost_dave'] == nil, 'joueur d\'une autre carte : pas de fantôme')
check(ghosts['grnfr_ghost_bob'].enter == false and entered == 1, 'les fantômes ne prennent pas le contrôle du joueur')
local names = table.concat(drawn, ',')
check(names:find('bob') and names:find('carol') and not names:find('dave'), 'pseudos affichés au-dessus des joueurs (' .. names:sub(1, 30) .. '...)')
check(ghosts['grnfr_ghost_bob'].pos.x > 1100, 'extrapolation avec la vitesse reçue')
check(grnfr_ghosts.isGhost(ghosts['grnfr_ghost_bob'].id), 'isGhost reconnaît un fantôme')
local nb = 0 for _ in pairs(objects) do nb = nb + 1 end
for _ = 1, 20 do grnfr_ghosts.update(0.1) end
local nb2 = 0 for _ in pairs(objects) do nb2 = nb2 + 1 end
check(nb == nb2, 'pas de réapparition en boucle')
-- bob change de voiture : l'ancienne disparaît, la nouvelle apparaît ; carol part : fantôme supprimé
payload = enc({ players = { { username = 'bob', level = wc, pos = { x = 1100, y = 1000, z = 0 }, rot = { 0, 0, 0, 1 }, vel = { 0, 0, 0 }, veh = { model = 'pickup' } } } })
grnfr_ghosts.onSync(payload)
for _ = 1, 60 do grnfr_ghosts.update(0.1) end
local g = {} for id, o in pairs(objects) do if o.name then g[o.name] = o end end
check(g['grnfr_ghost_bob'] and g['grnfr_ghost_bob'].model == 'pickup', 'bob a changé de véhicule : fantôme remplacé')
check(g['grnfr_ghost_carol'] == nil, 'carol est partie : fantôme supprimé')
check(#grnfr_ghosts.status().players == 1, 'état : 1 joueur distant')
grnfr_ghosts.setServer(false)
local left = 0 for id, o in pairs(objects) do if o.name then left = left + 1 end end
check(left == 0, 'quitter le serveur supprime tous les fantômes')
selfEvents = 0; guihooks.events = {}
for _ = 1, 20 do grnfr_ghosts.update(0.1) end
check(#guihooks.events == 0, 'hors serveur : plus aucun envoi de position')

-- ---------- 6. déconnexion
online.setAuth(false)
check(not online.isAuthed(), 'déconnecté')
print('=== SIMULATION LUA OK ===')
