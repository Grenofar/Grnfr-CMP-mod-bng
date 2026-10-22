-- GRNFR Online : garages physiques, un par place de serveur (4 par défaut, comme le nombre de joueurs max).
-- Chaque joueur qui a besoin d'un garage sur son serveur actuel en obtient un, à un endroit fixe (lieu nommé
-- "garage" proposé par le jeu si possible, sinon un point de route au hasard), mémorisé côté serveur
-- (supabase/migrations/0006_garage_spots.sql) : il reste au même endroit tant que son propriétaire reste sur
-- le serveur. La tablette (onglet Garage de la fenêtre GRNFR Online) ne s'ouvre qu'à proximité de SON garage ;
-- les autres garages du serveur sont visibles (marqueur au sol) mais jamais utilisables par quelqu'un d'autre.
-- Toutes les API du jeu sont sous pcall (hypothèses non vérifiées en jeu), comme le reste du mod.
local M = {}

local RADIUS = 10      -- m : distance d'activation de la tablette
local MARK_RANGE = 150 -- m : distance d'affichage des marqueurs au sol

local joined = false
local mine = nil        -- { slot, level, pos } une fois le garage obtenu
local others = {}        -- liste des autres garages du serveur : { slot, pos }
local claiming = false
local lastClaimTry = -99
local lastRefresh = -99
local near, dist = false, nil
local clock = 0
-- En arrivant sur un serveur, travel.lua charge la carte et place la voiture AVANT que le garage soit attribué
-- (sinon il le serait près du point d'apparition par défaut) : pendant ce temps, pas de demande de garage.
local holdUntil = nil
local HOLD_MAX = 120 -- s : sécurité si travel.lua ne libère jamais

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

function M.setServer(isJoined)
  isJoined = isJoined == true
  if isJoined ~= joined then slog('info', isJoined and 'Garage: joined a game server.' or 'Garage: left the game server.') end
  if isJoined and not joined then holdUntil = clock + HOLD_MAX end -- vient d'entrer : attend travel.lua
  joined = isJoined
  if not joined then M.reset(); holdUntil = nil end
  return true
end

function M.setHold(on) holdUntil = on and (clock + HOLD_MAX) or nil end

-- Mon garage sur ce serveur une fois attribué : { slot, level, pos }, sinon nil.
function M.mine() return mine end

-- Choisit un point candidat : un lieu nommé "garage" (le plus proche), sinon un point de route au hasard
-- entre 60 et 200 m du joueur. Envoyé au serveur seulement à la toute première demande (il ne sert plus après).
local function pickCandidate()
  local origin = grnfr_places.playerPos()
  if not origin then return nil end
  local best, bestD
  pcall(function()
    for _, p in ipairs(grnfr_places.pois()) do
      local n = tostring(p.name or ''):lower()
      if n:find('garage') then
        local d = grnfr_places.dist(p, origin)
        if not bestD or d < bestD then best, bestD = p, d end
      end
    end
  end)
  if best then return { x = best.x, y = best.y, z = best.z } end
  local n = grnfr_places.randomNear(origin, 60, 200)
  if n then return { x = n.x, y = n.y, z = n.z } end
end

local function requestClaim()
  local cand = pickCandidate()
  if not cand then return end -- pas encore de position : on retentera
  claiming = true
  grnfr_online.call('claim_garage_spot', { p_level = grnfr_places.level(), p_pos = cand }, function(ok, data)
    claiming = false
    if ok and type(data) == 'table' then
      mine = { slot = data.slot, level = data.level, pos = data.pos }
      slog('info', 'Garage: your garage on this server is at slot ' .. tostring(data.slot) .. '.')
    end
  end)
end

local function refreshOthers()
  grnfr_online.call('get_server_garage_spots', {}, function(ok, data)
    if not ok or type(data) ~= 'table' then return end
    local out = {}
    for _, g in ipairs(data) do
      if g.mine ~= true and type(g.pos) == 'table' then out[#out + 1] = { slot = g.slot, pos = g.pos } end
    end
    others = out
  end)
end

local function drawLabel(pos, label)
  pcall(function()
    local p = vec3(pos.x, pos.y, (pos.z or 0) + 1.4)
    if debugDrawer.drawTextAdvanced then
      debugDrawer:drawTextAdvanced(p, String(label), ColorF(1, 1, 1, 1), true, false, ColorI(0, 0, 0, 170))
    else
      debugDrawer:drawText(p, String(label), ColorF(1, 1, 1, 1))
    end
  end)
end

function M.update(dt)
  clock = clock + dt
  if not joined then near, dist = false, nil; return end
  if holdUntil and clock >= holdUntil then holdUntil = nil end
  if not mine and not claiming and not holdUntil and lastClaimTry + 3 <= clock then lastClaimTry = clock; requestClaim() end
  if lastRefresh + 5 <= clock then lastRefresh = clock; refreshOthers() end

  local p = grnfr_places.playerPos()
  if mine and mine.pos and p then
    dist = grnfr_places.dist(mine.pos, p)
    near = dist <= RADIUS
    if dist <= MARK_RANGE then drawLabel(mine.pos, near and 'GARAGE' or ('GARAGE (' .. math.floor(dist) .. ' m)')) end
  else
    near, dist = false, nil
  end
  if p then
    for _, g in ipairs(others) do
      local d = grnfr_places.dist(g.pos, p)
      if d <= MARK_RANGE then drawLabel(g.pos, 'GARAGE (autre joueur)') end
    end
  end
end

function M.isNear() return near end
function M.name() return mine and mine.name or nil end

function M.status()
  return { pos = mine and mine.pos or nil, slot = mine and mine.slot or nil, near = near, dist = dist and math.floor(dist) or nil }
end

function M.reset()
  mine, others, claiming = nil, {}, false
  near, dist = false, nil
  lastClaimTry, lastRefresh = -99, -99
end

return M
