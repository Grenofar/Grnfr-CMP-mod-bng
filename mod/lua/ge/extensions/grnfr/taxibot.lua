-- GRNFR Online : taxi IA. Le joueur appelle un taxi conduit par l'IA, monte dedans, et se fait emmener à destination.
-- Le prix est réservé (séquestre) par le serveur à l'appel : remboursé si le taxi est annulé avant l'embarquement.
-- Les API de véhicule (be:enterVehicle, ai.driveUsingPath, liste des configs "taxi") sont des hypothèses non vérifiées en jeu :
-- chaque appel est sous pcall, et un échec annule la course (remboursée).
local M = {}

local phase = 'idle'   -- idle | wait (le taxi arrive) | ride (en route) | arriving
local job, taxiId, prevId, dest = nil, nil, nil, nil
local timer, busy, retry = 0, false, 0
local lastMsg = ''
local WAIT_MAX = 240   -- s : au-delà, le taxi repart et la course est annulée

local function online() return rawget(_G, 'grnfr_online') end
local function L(fr, en) local o = online() return o and o.L(fr, en) or fr end
local function toast(m, k) local o = online() if o then o.toast(m, k) end end
local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

local function obj(id) if not id then return nil end local ok, o = pcall(function() return be:getObjectByID(id) end) if ok then return o end end
local function del(id) local o = obj(id) if o then pcall(function() o:delete() end) end end
local function enter(id) local o = obj(id) if o then pcall(function() be:enterVehicle(0, o) end) end end

-- Choisit une configuration « taxi » dans la liste du jeu ; repli sur un modèle de berline.
local function pickTaxi()
  local ok, l = pcall(function() return core_vehicles.getConfigList() end)
  if ok and type(l) == 'table' then
    for _, c in pairs(l.configs or l) do
      if type(c) == 'table' and c.model_key then
        local key = tostring(c.config_key or c.key or ''):lower()
        local name = tostring(c.Name or c.name or ''):lower()
        if key:find('taxi') or name:find('taxi') then return c.model_key, c.config_key or c.key end
      end
    end
  end
  return 'fullsize', nil
end

local function drive(id, node)
  local o = obj(id)
  if not (o and node) then return false end
  local cmd = string.format("ai.setMode('manual') if ai.driveUsingPath then ai.driveUsingPath{wpTargetList={'%s'},aggression=0.45,driveInLane='on',avoidCars='on'} else ai.setTarget('%s') end", node, node)
  return pcall(function() o:queueLuaCommand(cmd) end)
end

local function cleanup(refund)
  local o = online()
  if refund and job and o then o.call('cancel_job', { p_job = job.id }) end
  if phase == 'ride' or phase == 'arriving' then enter(prevId) end
  if taxiId then local t = taxiId; taxiId = nil; del(t) end
  phase, job, prevId, dest, timer, busy = 'idle', nil, nil, nil, 0, false
  grnfr_nav.clear()
end

-- d = { x, y, z, name } : destination choisie par le joueur
function M.call(d)
  local o = online()
  if not (o and o.isAuthed()) then toast(L('Connectez-vous d\'abord (touche O).', 'Sign in first (O key).'), 'warning') return false end
  if phase ~= 'idle' or type(d) ~= 'table' then return false end
  local pp = grnfr_nav.playerPos()
  if not pp then return false end
  local here = { x = pp.x, y = pp.y, z = pp.z }
  local to = { x = d.x, y = d.y, z = d.z or 0, node = d.node }
  local route = grnfr_places.routeLength(here, to)
  busy = true
  o.call('start_job', { p_kind = 'bot_taxi', p_level = grnfr_places.level(), p_pickup = here, p_dropoff = to, p_distance_m = route },
    function(ok, data)
      busy = false
      if not ok then toast(o.errText(data), 'error') return end
      job, dest = { id = data.id, fare = data.fare }, to
      -- apparition du taxi sur une route à 200-450 m, puis il rejoint le joueur
      local spot = grnfr_places.randomNear(pp, 200, 450)
      local model, cfg = pickTaxi()
      local okS, res = pcall(function()
        local opts = { autoEnterVehicle = false }
        if cfg then opts.config = cfg end
        if spot then opts.pos = vec3(spot.x, spot.y, spot.z + 0.5) end
        return core_vehicles.spawnNewVehicle(model, opts)
      end)
      if not okS or not res then
        slog('warn', 'Taxi bot: the game refused to spawn the taxi. Ride cancelled and refunded.')
        toast(L('Impossible de faire apparaître le taxi : course annulée et remboursée.', 'Could not spawn the taxi: ride cancelled and refunded.'), 'error')
        cleanup(true)
        return
      end
      taxiId = type(res) == 'number' and res or res:getID()
      drive(taxiId, grnfr_places.closestNode(pp))
      phase, timer = 'wait', 0
      toast(L('Taxi en route (', 'Taxi on its way (') .. '$' .. tostring(data.fare) .. L('). Attendez-le, il s\'arrêtera près de vous.', '). Wait for it; it will stop near you.'))
      slog('info', 'Taxi bot called.')
    end)
  return true
end

function M.cancel()
  if phase == 'idle' then return true end
  cleanup(phase == 'wait')
  toast(L('Taxi annulé.', 'Taxi cancelled.'))
  return true
end

local function dist(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end

function M.update(dt)
  if phase == 'idle' or busy then return end
  if retry > 0 then retry = retry - dt return end
  local o = online()
  local t = obj(taxiId)
  if not t then -- le taxi a disparu (supprimé par le joueur ou le jeu)
    toast(L('Le taxi a disparu : course annulée.', 'The taxi vanished: ride cancelled.'), 'warning')
    cleanup(phase == 'wait')
    return
  end
  timer = timer + dt
  local tp = t:getPosition()
  local tspeed = 0
  pcall(function() tspeed = t:getVelocity():length() end)
  if phase == 'wait' then
    local pp = grnfr_nav.playerPos()
    if timer > WAIT_MAX then toast(L('Le taxi n\'est pas arrivé à temps : course remboursée.', 'The taxi did not arrive in time: refunded.'), 'warning') cleanup(true) return end
    if pp and dist(tp, pp) <= 14 and tspeed < 3 then
      busy = true
      o.call('board_job', { p_job = job.id, p_pos = { x = pp.x, y = pp.y, z = pp.z } }, function(ok, data)
        busy = false
        if phase ~= 'wait' then return end
        if not ok then lastMsg = o.errText(data) retry = 3 return end
        local pv = be:getPlayerVehicle(0)
        prevId = pv and pv:getID() or nil
        enter(taxiId)
        drive(taxiId, dest.node or grnfr_places.closestNode(vec3(dest.x, dest.y, dest.z)))
        grnfr_nav.set(dest.x, dest.y, dest.z, L('Destination', 'Destination'), 40)
        phase, timer = 'ride', 0
        toast(L('Vous êtes à bord. Détendez-vous !', 'You are on board. Sit back!'))
      end)
    elseif timer % 20 < dt then -- relance régulière : l'IA peut s'être arrêtée en route
      drive(taxiId, grnfr_places.closestNode(pp or tp))
    end
  elseif phase == 'ride' then
    if dist(tp, dest) <= 35 and tspeed < 4 then
      busy = true
      o.call('complete_job', { p_job = job.id, p_pos = { x = tp.x, y = tp.y, z = tp.z } }, function(ok, data)
        busy = false
        if phase ~= 'ride' then return end
        if not ok then lastMsg = o.errText(data) retry = 3 return end
        toast(L('Arrivé ! Course payée : $', 'Arrived! Fare paid: $') .. tostring(job and job.fare or ''), 'success')
        slog('info', 'Taxi bot: ride completed.')
        cleanup(false)
      end)
    elseif timer > 1800 then cleanup(false) end
  end
end

function M.status()
  local d = dest and phase == 'ride' and grnfr_nav.distance()
  return { phase = phase, fare = job and job.fare or 0, dist = d and math.floor(d) or nil, msg = lastMsg }
end

function M.reset() cleanup(false) end

return M
