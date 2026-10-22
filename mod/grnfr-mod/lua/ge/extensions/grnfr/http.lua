-- GRNFR Online : transport HTTPS fait par le Lua du jeu.
--
-- Depuis BeamNG 0.40, l'interface (CEF) applique une Content-Security-Policy "connect-src 'self' localhost 127.0.0.1" :
-- tout fetch() de net.js vers Supabase est bloqué ("Failed to fetch"), pour tous les joueurs. net.js garde toute la
-- logique (session, jetons, erreurs) et confie ici l'envoi ; la réponse repart par l'événement GRNFRHttp.
--
-- Pourquoi un petit client maison : SecureComm.apiCall (client du moteur, v2.1.8) ne sert que l'API de BeamNG et ne
-- répondait jamais pour une autre adresse ; copas.http (livré avec le jeu) ne règle pas le SNI, que Cloudflare (devant
-- Supabase) exige. On utilise donc directement LuaSocket ('socket') + LuaSec ('ssl'), livrés avec le jeu, en mode
-- non bloquant : chaque requête est une coroutine qui avance un peu à chaque image (update), le jeu ne gèle jamais
-- (sauf la résolution DNS, brève et faite par le système).
-- Limite connue : le certificat du serveur n'est pas vérifié (verify = 'none' : le jeu ne fournit pas de magasin de
-- certificats) ; le chiffrement reste actif. Même philosophie "limité, pas infaillible" que l'anti-triche.
-- Ne JAMAIS journaliser l'URL complète (clé dans ?apikey=) ni l'en-tête Authorization (jeton de session).
local M = {}

local TIMEOUT = 15
local socket, ssl, libError
local jobs = {}

local function blog(level, msg) pcall(log, level, 'grnfr_http', msg) end

local function loadLibs()
  local okS, s = pcall(require, 'socket')
  local okL, l = pcall(require, 'ssl')
  if okS and type(s) == 'table' then socket = s end
  if okL and type(l) == 'table' then ssl = l end
  local detail
  if not socket then libError, detail = 'bibliothèque socket indisponible', tostring(s)
  elseif not ssl then libError, detail = 'bibliothèque ssl (LuaSec) indisponible', tostring(l) end
  if detail then libError = libError .. ' : ' .. (detail:match('[^\n]+') or detail) end
  blog(libError and 'E' or 'I', 'socket: ' .. (socket and tostring(socket._VERSION or 'ok') or 'ABSENT')
    .. ' | ssl: ' .. (ssl and tostring(ssl._VERSION or 'ok') or 'ABSENT') .. (detail and (' | ' .. detail) or ''))
end

local function reply(id, res)
  res.id = id
  pcall(function() guihooks.trigger('GRNFRHttp', res) end)
end

local function wouldBlock(err) return err == 'timeout' or err == 'wantread' or err == 'wantwrite' end

local function wrapTls(tcp)
  local lastErr
  -- 'any' = LuaSec >= 0.6, sinon noms plus anciens ; une option inconnue de la version livrée fait échouer wrap,
  -- d'où l'essai sans options en dernier recours.
  for _, proto in ipairs({ 'any', 'tlsv1_2', 'sslv23' }) do
    for _, opts in ipairs({ { 'all' }, false }) do
      local params = { mode = 'client', protocol = proto, verify = 'none' }
      if opts then params.options = opts end
      local okw, conn, err = pcall(ssl.wrap, tcp, params)
      if okw and conn then return conn end
      lastErr = okw and err or conn
    end
  end
  error('ssl.wrap : ' .. tostring(lastErr), 0)
end

-- Exécuté dans une coroutine : rend la main (yield) dès qu'une opération réseau devrait attendre.
local function run(job)
  local tcp = socket.tcp()
  tcp:settimeout(0)
  job.stage = 'connexion'
  local ok, err = tcp:connect(job.host, 443)
  if not ok and err ~= 'timeout' and not tostring(err):find('progress') then error('connexion à ' .. job.host .. ' : ' .. tostring(err), 0) end
  while true do
    local _, w = socket.select(nil, { tcp }, 0)
    if w and w[1] then break end
    coroutine.yield()
  end
  if not tcp:getpeername() then error('connexion à ' .. job.host .. ' refusée ou impossible', 0) end

  job.stage = 'chiffrement (TLS)'
  local conn = wrapTls(tcp)
  job.conn = conn
  if conn.sni then conn:sni(job.host) else blog('W', 'LuaSec sans SNI : Cloudflare risque de refuser la connexion') end
  conn:settimeout(0)
  while true do
    local hok, herr = conn:dohandshake()
    if hok then break end
    if not wouldBlock(herr) then error('TLS : ' .. tostring(herr), 0) end
    coroutine.yield()
  end

  job.stage = 'envoi'
  local data, i = job.raw, 1
  while i <= #data do
    local last, serr, partialLast = conn:send(data, i)
    if last then i = last + 1
    else
      if not wouldBlock(serr) then error('envoi : ' .. tostring(serr), 0) end
      if partialLast then i = partialLast + 1 end
      coroutine.yield()
    end
  end

  job.stage = 'réception'
  local parts = {}
  while true do
    local chunk, rerr, partial = conn:receive('*a')
    if chunk then parts[#parts + 1] = chunk break end
    if partial and #partial > 0 then parts[#parts + 1] = partial end
    if rerr == 'closed' then break end
    if not wouldBlock(rerr) then error('réception : ' .. tostring(rerr), 0) end
    coroutine.yield()
  end
  pcall(function() conn:close() end)
  return table.concat(parts)
end

local function dechunk(b)
  local out, pos = {}, 1
  while true do
    local sizeHex, nextPos = b:match('^(%x+)[^\r\n]*\r\n()', pos)
    if not sizeHex then break end
    local size = tonumber(sizeHex, 16)
    if not size or size == 0 then break end
    out[#out + 1] = b:sub(nextPos, nextPos + size - 1)
    pos = nextPos + size + 2
  end
  return table.concat(out)
end

local function parse(resp)
  local head, body = resp:match('^(.-)\r\n\r\n(.*)$')
  if not head then error('réponse illisible (' .. #resp .. ' octets)', 0) end
  local status = tonumber(head:match('^HTTP/%d%.?%d? (%d%d%d)'))
  if not status then error('ligne de statut illisible', 0) end
  if head:lower():find('transfer%-encoding:%s*chunked') then body = dechunk(body) end
  return status, body
end

local function finish(job, res)
  for i = #jobs, 1, -1 do if jobs[i] == job then table.remove(jobs, i) end end
  if job.conn then pcall(function() job.conn:close() end) end
  blog(res.error and 'W' or 'I', ('#%d %s -> %s'):format(job.id, job.label, res.error or tostring(res.status)))
  reply(job.id, res)
end

local function step(job)
  local ok, res = coroutine.resume(job.co, job)
  if not ok then return finish(job, { status = 0, error = tostring(res) }) end
  if coroutine.status(job.co) == 'dead' then
    local pok, status, body = pcall(parse, res or '')
    if pok then finish(job, { status = status, body = body })
    else finish(job, { status = 0, error = tostring(status) }) end
  end
end

-- Appelé par net.js (engineLua). method = 'get' | 'post', body = texte JSON ('' si aucun), authorization = "Bearer ...".
function M.request(id, method, url, body, authorization)
  if libError then reply(id, { status = 0, error = libError }) return true end
  local host, path = tostring(url):match('^https://([^/]+)(/.*)$')
  if not host then reply(id, { status = 0, error = 'adresse invalide' }) return true end
  body = body or ''
  method = method == 'get' and 'GET' or 'POST'
  local job = {
    id = id, host = host, age = 0, stage = 'attente',
    label = method .. ' ' .. path:gsub('%?.*', ''),
    raw = table.concat({
      method .. ' ' .. path .. ' HTTP/1.1',
      'Host: ' .. host,
      'User-Agent: GRNFR-CMP',
      'Accept: application/json',
      'Content-Type: application/json',
      'Authorization: ' .. tostring(authorization or ''),
      'Content-Length: ' .. #body,
      'Connection: close',
      '', body,
    }, '\r\n'),
  }
  job.co = coroutine.create(run)
  jobs[#jobs + 1] = job
  step(job)
  return true
end

-- Appelé à chaque image par grnfr.lua (M.tick), y compris dans le menu principal.
function M.update(dt)
  for i = #jobs, 1, -1 do
    local job = jobs[i]
    if job then
      job.age = job.age + (tonumber(dt) or 0)
      if job.age > TIMEOUT then finish(job, { status = 0, error = 'délai dépassé pendant : ' .. job.stage })
      else step(job) end
    end
  end
end

function M.onExtensionLoaded() loadLibs() end

return M
