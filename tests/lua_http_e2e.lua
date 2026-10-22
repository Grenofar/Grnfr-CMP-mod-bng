-- Vrai mod/grnfr-mod/lua/ge/extensions/grnfr/http.lua, dans un vrai LuaJIT + LuaSocket (comme BeamNG), contre le
-- vrai relais de GRNFR CMP Launcher (lancé par tests/launcher_e2e.mjs). Usage : luajit tests/lua_http_e2e.lua up|down
local mode = arg[1] or 'up'
local socket = require('socket')
local events, logs = {}, {}
log = function(level, tag, msg) logs[#logs + 1] = level .. ' ' .. msg end
guihooks = { trigger = function(name, data) events[#events + 1] = { name = name, data = data } end }

local M = dofile('mod/grnfr-mod/lua/ge/extensions/grnfr/http.lua')
M.onExtensionLoaded()

local function call(id, method, path, body, auth)
  local before = #events
  M.request(id, method, path, body, 'anon', auth)
  local t0 = socket.gettime()
  while #events == before and socket.gettime() - t0 < 10 do
    M.update(0.016)
    socket.sleep(0.005)
  end
  local e = events[#events]
  assert(#events > before and e.name == 'GRNFRHttp' and e.data.id == id, 'pas de réponse GRNFRHttp pour #' .. id)
  return e.data
end

local function check(c, what) if not c then error('ECHEC : ' .. what) end print('ok   [lua] ' .. what) end

if mode == 'up' then
  local r = call(1, 'post', '/auth/v1/signup', '{}', 'Bearer anon')
  check(r.status == 200 and r.body:find('"access_token":"tok'), 'inscription anonyme via LuaSocket -> relais -> serveur (' .. tostring(r.status) .. ' ' .. tostring(r.error) .. ')')
  local tok = r.body:match('"access_token":"([^"]+)"')
  r = call(2, 'post', '/rest/v1/rpc/set_username', '{"p_username":"lua_user"}', 'Bearer ' .. tok)
  check(r.status == 200, 'RPC authentifiée (jeton en Authorization) : ' .. tostring(r.status))
  r = call(3, 'post', '/rest/v1/rpc/get_me', '{}', 'Bearer ' .. tok)
  check(r.status == 200 and r.body:find('"username":"lua_user"'), 'corps JSON relu en entier : ' .. r.body)
  r = call(4, 'post', '/rest/v1/rpc/fonction_inconnue', '{}', 'Bearer ' .. tok)
  check(r.status == 404 and r.body:find('unknown_fn'), 'erreur du serveur relayée avec son statut')
  r = call(5, 'get', '/storage/v1/x', '', 'Bearer anon')
  check(r.status == 0 and r.error == 'chemin refusé', 'chemin hors /rest et /auth refusé avant tout envoi')
  for _, l in ipairs(logs) do assert(not l:find('Bearer'), 'jeton dans le journal : ' .. l) end
  check(true, 'aucun jeton dans le journal (' .. #logs .. ' lignes)')
else
  local r = call(6, 'post', '/auth/v1/signup', '{}', 'Bearer anon')
  check(r.status == 0 and r.error:find('launcher injoignable'), 'launcher fermé : erreur claire (' .. tostring(r.error) .. ')')
end
print('=== LUA OK (' .. mode .. ') ===')
