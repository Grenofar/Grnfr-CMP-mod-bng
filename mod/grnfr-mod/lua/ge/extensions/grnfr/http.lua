-- GRNFR Online : transport HTTPS par le moteur du jeu.
--
-- Depuis BeamNG 0.40, l'interface (CEF) applique une Content-Security-Policy "connect-src 'self' localhost 127.0.0.1" :
-- tout fetch() de net.js vers Supabase est bloqué ("Failed to fetch"), quel que soit le réseau du joueur. On passe donc
-- par le client HTTP natif du moteur (curl, celui de core_online / du repo de mods), que cette règle ne concerne pas.
-- net.js garde toute la logique (session, jetons, erreurs) : ce module ne fait qu'envoyer la requête et rendre la réponse
-- (événement GRNFRHttp). Ne JAMAIS journaliser l'URL complète ni authorization : ils contiennent la clé et le jeton.
--
-- API non vérifiée (déduite de lua/ge/extensions/core/online.lua de la 0.40) : SecureComm.apiCall(t) avec
-- t.url, t.reqType ('get'/'post'), t.postDataString, t.isJson, t.authorizationHeader, t.id, et t.callback_finish_c =
-- chemin Lua de la fonction rappelée par le C++ avec (id, code, buffer, headers, data, post, curlCode, curlErr, url).
local M = {}

-- Décalage des identifiants : le C++ appelle aussi core_online.clearRequest(id) en fin de requête, on évite donc
-- de partager la plage d'identifiants de core_online (qui commence à 0).
local ID_BASE = 7000000

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

local function reply(id, res)
  res.id = id
  pcall(function() guihooks.trigger('GRNFRHttp', res) end)
end

-- Appelé par net.js (engineLua). method = 'get' | 'post', body = texte JSON ('' si aucun), authorization = "Bearer ...".
function M.request(id, method, url, body, authorization)
  local sc = rawget(_G, 'SecureComm')
  if not sc or type(sc.apiCall) ~= 'function' then
    slog('problem', 'HTTP: SecureComm.apiCall is not available in this game version.')
    reply(id, { status = 0, error = 'SecureComm.apiCall indisponible dans cette version du jeu' })
    return true
  end
  local ok, err = pcall(sc.apiCall, {
    id = ID_BASE + id,
    url = url,
    reqType = method == 'get' and 'get' or 'post',
    postDataString = body or '',
    postFileName = '',
    isJson = true,
    authorizationHeader = authorization,
    callback_finish_c = 'grnfr_http.onDone',
  })
  if not ok then
    slog('problem', 'HTTP: the game refused to send a request.')
    reply(id, { status = 0, error = 'SecureComm.apiCall : ' .. tostring(err) })
  end
  return true
end

-- Appelé par le C++ à la fin de la requête.
function M.onDone(id, responseCode, responseBuffer, responseHeaders, responseData, postData, curlCode, curlErrorStr)
  local body = ''
  if type(responseBuffer) == 'string' and responseBuffer ~= '' then
    body = responseBuffer
  elseif responseData ~= nil then
    local okj, s = pcall(jsonEncode, responseData)
    if okj and type(s) == 'string' then body = s end
  end
  local res = { status = tonumber(responseCode) or 0, body = body }
  if curlCode and curlCode ~= 0 then
    res.error = 'curl ' .. tostring(curlCode) .. ' : ' .. tostring(curlErrorStr or '')
    slog('problem', 'HTTP: request failed (curl ' .. tostring(curlCode) .. ').')
  end
  reply((tonumber(id) or ID_BASE) - ID_BASE, res)
end

-- core_online expose aussi clearRequest au C++ : présent ici au cas où le moteur l'appelle sur ce module.
function M.clearRequest() end

return M
