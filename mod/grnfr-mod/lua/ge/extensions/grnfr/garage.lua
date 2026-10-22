-- GRNFR Online : un garage par joueur et par serveur, toujours dans un VRAI garage de la carte (grnfr/facilities.lua :
-- garages de la carrière du jeu, avec leur ordinateur = la tablette GRNFR). Jamais au hasard sur la route : une carte
-- sans garages n'en donne pas. Le serveur (supabase/migrations/0006_garage_spots.sql) retient QUI a QUEL garage
-- (position de la tablette) tant que son propriétaire reste sur le serveur ; deux joueurs n'ont jamais le même.
-- La tablette (touche O) ne s'ouvre qu'à proximité de SON garage ; ceux des autres sont signalés mais inutilisables.
-- Un garage attribué par une ancienne version (au hasard sur la route) est rendu puis remplacé automatiquement.
local M = {}

local RADIUS = 12      -- m : distance d'utilisation de la tablette (depuis la tablette ou une place du garage)
local MARK_RANGE = 150 -- m : distance d'affichage des repères
local TAKEN = 25       -- m : un garage est pris si un autre joueur a déjà sa tablette à moins de ça

local joined = false
local mine = nil        -- { slot, level, pos, garage = entrée de facilities.garages() ou nil }
local others = {}       -- autres garages du serveur : { slot, pos }
local claiming = false
local lastClaimTry = -99
local lastRefresh = -99
local near, dist = false, nil
local clock = 0
local noGarageWarned = nil
-- En arrivant sur un serveur, travel.lua charge la carte et place la voiture AVANT que le garage soit attribué :
-- pendant ce temps, pas de demande de garage.
local holdUntil = nil
local HOLD_MAX = 120 -- s : sécurité si travel.lua ne libère jamais

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local function L(fr, en) return grnfr_online.L(fr, en) end

function M.setServer(isJoined)
  isJoined = isJoined == true
  if isJoined ~= joined then slog('info', isJoined and 'Garage: joined a game server.' or 'Garage: left the game server.') end
  if isJoined and not joined then holdUntil = clock + HOLD_MAX end -- vient d'entrer : attend travel.lua
  joined = isJoined
  if not joined then M.reset(); holdUntil = nil end
  return true
end

function M.setHold(on) holdUntil = on and (clock + HOLD_MAX) or nil end

-- Tous les vrais garages de la carte, triés du plus proche au plus loin (ceux avec ordinateur d'abord) : la
-- liste ENTIÈRE (pas juste le meilleur) est envoyée au serveur, qui choisit lui-même le premier non pris (voir
-- requestClaim) — ça évite la course entre deux joueurs qui rejoignent presque en même temps : avant, chacun
-- calculait de son côté le "meilleur garage libre" d'après un cache local pas toujours à jour (rafraîchi toutes
-- les 5 s), et pouvait recevoir le MÊME garage que l'autre.
local function sortedGarages()
  local origin = grnfr_places.playerPos()
  if not origin then return {} end
  local list = {}
  for _, g in ipairs(grnfr_facilities.garages()) do list[#list + 1] = g end
  table.sort(list, function(a, b)
    local sa = grnfr_facilities.dist(a.tablet, origin) + (a.hasComputer and 0 or 100000)
    local sb = grnfr_facilities.dist(b.tablet, origin) + (b.hasComputer and 0 or 100000)
    return sa < sb
  end)
  return list
end

local function requestClaim()
  local list = sortedGarages()
  if #list == 0 then
    if noGarageWarned ~= grnfr_places.level() then
      noGarageWarned = grnfr_places.level()
      grnfr_online.toast(L('Aucun garage libre sur cette carte.', 'No free garage on this map.'), 'warning')
    end
    return
  end
  claiming = true
  local candidates = {}
  for i, g in ipairs(list) do candidates[i] = { x = g.tablet.x, y = g.tablet.y, z = g.tablet.z } end
  grnfr_online.call('claim_garage_spot', { p_level = grnfr_places.level(), p_candidates = candidates }, function(ok, data)
    claiming = false
    -- Le serveur n'a pas pu enregistrer le garage : on prend quand même le plus proche, ici seulement (il sera
    -- enregistré à la prochaine arrivée). Le joueur n'attend jamais devant un garage qui n'existe pas.
    local function useLocally(why)
      local g = list[1]
      slog('warn', 'Garage: ' .. why .. ', using ' .. g.name .. ' on this machine only.')
      mine = { slot = nil, level = grnfr_places.level(), pos = { x = g.tablet.x, y = g.tablet.y, z = g.tablet.z }, garage = g, localOnly = true }
    end
    if not (ok and type(data) == 'table' and type(data.pos) == 'table') then useLocally('the server refused the garage (' .. tostring(data) .. ')') return end
    local real = (data.level == nil or data.level == grnfr_places.level()) and grnfr_facilities.at(data.pos, 30) or nil
    if not real and data.level == grnfr_places.level() then
      -- ancien garage au hasard sur la route : on le rend, la prochaine demande en donnera un vrai
      slog('info', 'Garage: the server gave an old garage that is not a real garage, giving it back.')
      grnfr_online.call('release_garage_spot', {}, function(ok2)
        if ok2 then lastClaimTry = clock - 2 else useLocally('could not give the old garage back (server not up to date)') end
      end)
      return
    end
    mine = { slot = data.slot, level = data.level, pos = data.pos, garage = real }
    slog('info', 'Garage: your garage on this server is ' .. tostring(real and real.name or ('slot ' .. tostring(data.slot))) .. '.')
  end)
end

local function refreshOthers()
  grnfr_online.call('get_server_garage_spots', {}, function(ok, data)
    if not ok or type(data) ~= 'table' then return end
    local out = {}
    for _, g in ipairs(data) do
      if g.mine ~= true and type(g.pos) == 'table' then out[#out + 1] = { slot = g.slot, pos = g.pos, username = g.username } end
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

-- Distance à mon garage : la tablette ou n'importe laquelle de ses places de parking.
local function distToMine(p)
  if not (mine and mine.pos and p) then return nil end
  local d = grnfr_facilities.dist(mine.pos, p)
  if mine.garage then for _, s in ipairs(mine.garage.spots) do d = math.min(d, grnfr_facilities.dist(s.pos, p)) end end
  return d
end

function M.update(dt)
  clock = clock + dt
  if not joined then near, dist = false, nil; return end
  if holdUntil and clock >= holdUntil then holdUntil = nil end
  if not mine and not claiming and not holdUntil and lastClaimTry + 3 <= clock then lastClaimTry = clock; requestClaim() end
  if lastRefresh + 5 <= clock then lastRefresh = clock; refreshOthers() end

  local p = grnfr_places.playerPos()
  dist = distToMine(p)
  near = dist ~= nil and dist <= RADIUS
  if mine and mine.pos and p and grnfr_facilities.dist(mine.pos, p) <= MARK_RANGE then
    local name = mine.garage and mine.garage.name or L('Mon garage', 'My garage')
    drawLabel(mine.pos, near and (L('Tablette GRNFR — touche O', 'GRNFR tablet — O key')) or (name .. ' (' .. math.floor(dist or 0) .. ' m)'))
  end
  if p then
    for _, g in ipairs(others) do
      if grnfr_facilities.dist(g.pos, p) <= MARK_RANGE then
        drawLabel(g.pos, g.username and (L('Garage de ', 'Garage of ') .. g.username) or L('Garage d\'un autre joueur', 'Another player\'s garage'))
      end
    end
    -- vrais garages de la carte que personne n'a (encore) pris : "Garage non pris".
    for _, g in ipairs(grnfr_facilities.garages()) do
      local taken = (mine and mine.garage and mine.garage.id == g.id)
      if not taken then for _, o in ipairs(others) do if grnfr_facilities.dist(g.tablet, o.pos) < TAKEN then taken = true break end end end
      if not taken and grnfr_facilities.dist(g.tablet, p) <= MARK_RANGE then drawLabel(g.tablet, L('Garage non pris', 'Unclaimed garage')) end
    end
  end
end

function M.isNear() return near end
function M.name() return mine and mine.garage and mine.garage.name or nil end
-- Mon garage sur ce serveur une fois attribué : { slot, level, pos, garage }, sinon nil.
function M.mine() return mine end

local function spotBusy(pos)
  local busy = false
  pcall(function()
    for i = 0, be:getObjectCount() - 1 do
      local o = be:getObject(i)
      local op = o and o:getPosition()
      if op and grnfr_facilities.dist(op, pos) < 3 then busy = true break end
    end
  end)
  return busy
end

-- Une place de parking libre de mon garage (pos, rot) pour y faire apparaître un véhicule. Si TOUTES les places
-- enregistrées semblent occupées (plusieurs voitures/fantômes au même garage), on ne force plus bêtement la
-- première place (risque de faire apparaître la voiture DANS une autre) : on décale en rond autour d'elle
-- jusqu'à trouver un point libre, à défaut la place d'origine (mieux qu'un blocage complet).
function M.freeSpot()
  if not (mine and mine.garage) then return nil end
  for _, s in ipairs(mine.garage.spots) do
    if not spotBusy(s.pos) then return s end
  end
  local s = mine.garage.spots[1]
  if not s then return nil end
  for _, a in ipairs({ 45, 90, 135, 180, 225, 270, 315 }) do
    local rad = math.rad(a)
    local p = { x = s.pos.x + 5 * math.cos(rad), y = s.pos.y + 5 * math.sin(rad), z = s.pos.z }
    if not spotBusy(p) then
      slog('info', 'Garage: all registered spots looked busy, using a safe spot next to ' .. tostring(mine.garage.name) .. '.')
      return { pos = p, rot = s.rot }
    end
  end
  return s
end

-- Place le véhicule du joueur sur une place de son garage (sinon à côté de la tablette), puis VÉRIFIE qu'il y est :
-- freeroam_facilities.teleportToGarage (carrière) ne fait rien, sans erreur, quand il ne trouve pas de place, d'où
-- plusieurs méthodes essayées tour à tour. Renvoie true si le véhicule est bien au garage.
function M.teleportHome(veh)
  if not (mine and veh) then return false end
  local s = M.freeSpot()
  local p = s and vec3(s.pos.x, s.pos.y, s.pos.z + 0.5) or vec3(mine.pos.x + 3, mine.pos.y + 3, mine.pos.z + 0.5)
  local r = s and s.rot or quat(0, 0, 0, 1)
  local function arrived()
    local ok, cur = pcall(function() return veh:getPosition() end)
    return ok and cur and grnfr_facilities.dist(cur, p) < 15
  end
  local tries = {
    { 'spawn.safeTeleport', function() spawn.safeTeleport(veh, p, r) end },
    { 'setPositionRotation', function() veh:setPositionRotation(p.x, p.y, p.z, r.x or r[1] or 0, r.y or r[2] or 0, r.z or r[3] or 0, r.w or r[4] or 1) end },
    { 'teleportToGarage', function() freeroam_facilities.teleportToGarage(mine.garage.id, veh, false) end },
  }
  for _, t in ipairs(tries) do
    local ok, err = pcall(t[2])
    if ok and arrived() then slog('info', 'Garage: player placed at the garage (' .. t[1] .. ').') return true end
    slog('warn', 'Garage: ' .. t[1] .. ' did not move the player to the garage' .. (ok and '' or (' (' .. tostring(err) .. ')')) .. '.')
  end
  return false
end

function M.status()
  return { pos = mine and mine.pos or nil, slot = mine and mine.slot or nil, name = M.name(), near = near, dist = dist and math.floor(dist) or nil }
end

function M.reset()
  mine, others, claiming = nil, {}, false
  near, dist = false, nil
  lastClaimTry, lastRefresh = -99, -99
end

return M
