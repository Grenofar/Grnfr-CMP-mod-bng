-- GRNFR Online : second chemin vers GRNFR CMP Launcher, par le Lua du jeu.
--
-- Chemin principal : net.js fait fetch("http://127.0.0.1:30815/...") depuis l'interface (autorisé par la CSP de
-- BeamNG 0.40). Si l'interface n'y arrive pas (restrictions réseau local du navigateur intégré, constatées en jeu
-- alors que le launcher était ouvert), net.js passe par ici : le Lua du jeu a LuaSocket (pas de TLS, mais il n'en faut
-- pas pour parler au launcher sur la même machine) et fait la même requête en HTTP simple. Réponse renvoyée par
-- l'événement GRNFRHttp.
-- Ne parle QU'À 127.0.0.1:30815 (le launcher) : on ne reçoit qu'un chemin, jamais une adresse.
-- Non bloquant : une coroutine par requête, avancée à chaque image par update() (appelé par grnfr.lua, M.tick).
-- Ne JAMAIS journaliser l'en-tête Authorization (jeton de session).
local M = {}

local HOST, PORT = '127.0.0.1', 30815
local TIMEOUT = 20
local socket, libError
local jobs = {}

local function blog(level, msg) pcall(log, level, 'grnfr_http', msg) end

local function loadLibs()
  local ok, s = pcall(require, 'socket')
  if ok and type(s) == 'table' then socket = s
  else libError = 'LuaSocket indisponible : ' .. (tostring(s):match('[^\n]+') or '?') end
  blog(libError and 'E' or 'I', 'socket: ' .. (socket and tostring(socket._VERSION or 'ok') or 'ABSENT'))
end

local function reply(id, res)
  res.id = id
  pcall(function() guihooks.trigger('GRNFRHttp', res) end)
end

local function wouldBlock(err) return err == 'timeout' or err == 'wantread' or err == 'wantwrite' end

-- Dans une coroutine : rend la main (yield) dès qu'une opération réseau devrait attendre.
local function run(job)
  local tcp = socket.tcp()
  job.conn = tcp
  tcp:settimeout(0)
  job.stage = 'connexion au launcher'
  local ok, err = tcp:connect(HOST, PORT)
  if not ok and err ~= 'timeout' and not tostring(err):find('progress') then
    error('launcher injoignable sur ' .. HOST .. ':' .. PORT .. ' (' .. tostring(err) .. ')', 0)
  end
  while true do
    local _, w = socket.select(nil, { tcp }, 0)
    if w and w[1] then break end
    coroutine.yield()
  end
  if not tcp:getpeername() then error('launcher injoignable sur ' .. HOST .. ':' .. PORT .. ' (connexion refusée)', 0) end

  job.stage = 'envoi'
  local data, i = job.raw, 1
  while i <= #data do
    local last, serr, partialLast = tcp:send(data, i)
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
    local chunk, rerr, partial = tcp:receive('*a')
    if chunk then parts[#parts + 1] = chunk break end
    if partial and #partial > 0 then parts[#parts + 1] = partial end
    if rerr == 'closed' then break end
    if not wouldBlock(rerr) then error('réception : ' .. tostring(rerr), 0) end
    coroutine.yield()
  end
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
  if not head then error('réponse illisible du launcher (' .. #resp .. ' octets)', 0) end
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

-- Appelé par net.js (engineLua). path = "/rest/v1/..." ou "/auth/v1/...", method = 'get' | 'post',
-- body = texte JSON ('' si aucun), apikey = clé anon publique, authorization = "Bearer ...".
function M.request(id, method, path, body, apikey, authorization)
  if libError then reply(id, { status = 0, error = libError }) return true end
  path = tostring(path or '')
  if not (path:find('^/rest/v1/') or path:find('^/auth/v1/')) then reply(id, { status = 0, error = 'chemin refusé' }) return true end
  body = body or ''
  method = method == 'get' and 'GET' or 'POST'
  local job = {
    id = id, age = 0, stage = 'attente',
    label = method .. ' ' .. path:gsub('%?.*', ''),
    raw = table.concat({
      method .. ' ' .. path .. ' HTTP/1.1',
      'Host: ' .. HOST .. ':' .. PORT,
      'User-Agent: GRNFR-CMP-mod',
      'Accept: application/json',
      'Content-Type: application/json',
      'apikey: ' .. tostring(apikey or ''),
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
