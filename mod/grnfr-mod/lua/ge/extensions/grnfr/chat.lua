-- GRNFR Online : chat textuel entre joueurs du même serveur de jeu (téléphone, touche K par défaut).
-- Les messages passent par le pont RPC générique (grnfr_online.call), comme toutes les autres actions GRNFR
-- Online : aucune nouvelle plomberie réseau n'est nécessaire côté interface (net.js).
local M = {}

local joined = false
local log = {}  -- { { id, username, text, created_at }, ... } (du plus ancien au plus récent)
local acc = 0
local POLL = 2 -- s

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

function M.setServer(isJoined)
  joined = isJoined == true
  if not joined then M.reset() end
end

function M.send(text)
  if not joined then return end
  text = tostring(text or ''):sub(1, 200)
  if text == '' then return end
  grnfr_online.call('send_chat_message', { p_text = text }, function(ok, err)
    if ok then M.poll() else slog('warn', 'Chat message refused: ' .. tostring(err)) end
  end)
end

function M.poll()
  if not joined then return end
  grnfr_online.call('get_chat_messages', { p_limit = 50 }, function(ok, data)
    if ok and type(data) == 'table' then log = data end
  end)
end

function M.update(dt)
  if not joined then return end
  acc = acc + dt
  if acc >= POLL then acc = 0; M.poll() end
end

function M.status() return { joined = joined, messages = log } end

function M.reset() log, acc = {}, 0 end

return M
