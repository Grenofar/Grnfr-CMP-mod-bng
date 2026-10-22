-- GRNFR Online : le joueur est chauffeur de taxi.
--   * 'npc' : passagers PNJ générés sur des routes crédibles (payés par le serveur, plafonnés par heure) ;
--   * 'req' : course demandée par un autre joueur (payée par ce joueur, argent mis sous séquestre par le serveur).
-- Déroulé : se rendre au départ -> s'arrêter (embarquement validé par le serveur) -> se rendre à l'arrivée -> s'arrêter
-- (paiement validé par le serveur : position, durée crédible, plafond horaire). Le jeu ne décide jamais d'un montant.
local M = {}

local duty = false
local job = nil          -- { kind='npc'|'req', id, pickup={x,y,z}, dropoff={x,y,z}, fare, name, phase }
local busy = false       -- un appel serveur est en cours
local cooldown = 0
local retry = 0
local lastMsg = ''
local earned = 0         -- gains de la session (affichage)
local rides = 0

-- Douceur de conduite (grand chantier Phase C, 22/10/2026) : pendant que le passager est à bord (phase dropoff),
-- on échantillonne l'accélération subie à chaque image (delta de vitesse / dt, une approximation du G-force,
-- pas une mesure physique exacte) et on garde l'excès au-delà d'un seuil tolérable (freinage/virage normal).
-- À l'arrivée, converti en score 0-100 envoyé au serveur (private.comfort_tip, 0023_vehicle_classes.sql) : le
-- serveur décide seul du pourboire ou du refus de payer, jamais le client.
local comfortAcc, comfortSamples, lastVel = 0, 0, nil
local COMFORT_TOLERANCE = 3   -- m/s^2 : jusque là, freinage/virage considéré normal, pas de pénalité
local COMFORT_SCALE = 10      -- m/s^2 d'excès moyen -> ~0 de douceur

local function playerVeh2() local ok, v = pcall(function() return be:getPlayerVehicle(0) end) if ok then return v end end
local function vehModel()
  local v = playerVeh2()
  if not v then return nil, nil end
  local ok, model = pcall(function() return tostring(v.jbeam or '') end)
  local config
  pcall(function()
    local pc = v.partConfig
    if type(pc) == 'string' then config = pc:match('([^/\\]+)%.pc$') end
  end)
  return ok and model ~= '' and model or nil, config
end

local function resetComfort() comfortAcc, comfortSamples, lastVel = 0, 0, nil end

local function sampleComfort(dt)
  local v = playerVeh2()
  if not v or not dt or dt <= 0 then return end
  local ok, vel = pcall(function() return v:getVelocity() end)
  if not ok or not vel then return end
  if lastVel then
    local dvx, dvy, dvz = vel.x - lastVel.x, vel.y - lastVel.y, vel.z - lastVel.z
    local acc = math.sqrt(dvx * dvx + dvy * dvy + dvz * dvz) / dt
    comfortAcc = comfortAcc + math.max(0, acc - COMFORT_TOLERANCE)
    comfortSamples = comfortSamples + 1
  end
  lastVel = { x = vel.x, y = vel.y, z = vel.z }
end

-- 100 = conduite parfaitement douce, 0 = très brusque. Pas assez d'échantillons (trajet très court) -> 100 par défaut.
local function comfortScore()
  if comfortSamples <= 0 then return 100 end
  local avgExcess = comfortAcc / comfortSamples
  return math.max(0, math.min(100, math.floor(100 - avgExcess * (100 / COMFORT_SCALE) + 0.5)))
end

local function online() return rawget(_G, 'grnfr_online') end
local function L(fr, en) local o = online() return o and o.L(fr, en) or fr end
local function toast(m, k) local o = online() if o then o.toast(m, k) end end
local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

local function clearJob()
  job, busy = nil, false
  grnfr_nav.clear()
end

local function fmtMoney(n) return '$' .. tostring(math.floor(tonumber(n) or 0)) end

-- ------------------------------------------------------------------ course PNJ
local function newNpcFare()
  if busy or job or not duty then return end
  local o = online()
  local origin = grnfr_places.playerPos()
  if not (o and o.isAuthed() and origin) then return end
  local pickup = grnfr_places.randomNear(origin, 250, 1300)
  if not pickup then lastMsg = L('Aucune route trouvée autour de vous.', 'No road found around you.') return end
  local dropoff = grnfr_places.randomNear(pickup, 1200, 4500)
  if not dropoff then return end
  local route = grnfr_places.routeLength(pickup, dropoff)
  busy = true
  o.call('start_job', { p_kind = 'npc_taxi', p_level = grnfr_places.level(), p_pickup = grnfr_places.xyz(pickup),
    p_dropoff = grnfr_places.xyz(dropoff), p_distance_m = route }, function(ok, data)
    busy = false
    if not duty then return end
    if not ok then lastMsg = o.errText(data) retry = 8 return end
    job = { kind = 'npc', id = data.id, pickup = grnfr_places.xyz(pickup), dropoff = grnfr_places.xyz(dropoff),
      fare = data.fare, name = L('Passager', 'Passenger'), phase = 'pickup' }
    grnfr_nav.set(pickup.x, pickup.y, pickup.z, L('Passager', 'Passenger'), 30)
    toast(L('Nouveau passager : rendez-vous au point orange. Course estimée : ', 'New passenger: go to the orange marker. Estimated fare: ') .. fmtMoney(data.fare))
  end)
end

-- ------------------------------------------------------------------ course d'un autre joueur
-- r = ligne renvoyée par get_open_taxi_requests : { id, passenger, pickup={x,y,z}, dropoff={x,y,z}, fare }
function M.acceptRequest(r)
  local o = online()
  if not (o and o.isAuthed()) or type(r) ~= 'table' or not r.id then return false end
  if job and job.kind == 'req' then toast(L('Une course est déjà en cours.', 'A ride is already in progress.'), 'warning') return false end
  if job and job.kind == 'npc' then -- on abandonne le passager PNJ
    o.call('cancel_job', { p_job = job.id })
    clearJob()
  end
  busy = true
  o.call('accept_taxi_request', { p_id = r.id }, function(ok, data)
    busy = false
    if not ok then toast(o.errText(data), 'error') return end
    job = { kind = 'req', id = r.id, pickup = r.pickup, dropoff = r.dropoff, fare = r.fare, name = tostring(r.passenger or '?'), phase = 'pickup' }
    grnfr_nav.set(r.pickup.x, r.pickup.y, r.pickup.z or 0, tostring(r.passenger or ''), 30)
    toast(L('Course acceptée : allez chercher ', 'Ride accepted: pick up ') .. tostring(r.passenger))
  end)
  return true
end

-- ------------------------------------------------------------------ déroulé commun
local function board()
  local o, p = online(), grnfr_nav.playerPos()
  if not (o and p) then return end
  busy = true
  local fn, args
  if job.kind == 'req' then fn, args = 'taxi_pickup', { p_id = job.id, p_pos = grnfr_places.xyz(p) }
  else fn, args = 'board_job', { p_job = job.id, p_pos = grnfr_places.xyz(p) } end
  o.call(fn, args, function(ok, data)
    busy = false
    if not job then return end
    if not ok then
      lastMsg = o.errText(data)
      if data == 'job_unavailable' or data == 'request_unavailable' then clearJob() else retry = 4 end
      return
    end
    job.phase = 'dropoff'
    resetComfort()
    grnfr_nav.set(job.dropoff.x, job.dropoff.y, job.dropoff.z or 0, L('Destination', 'Destination'), 35)
    toast(L('Passager à bord. Direction la destination !', 'Passenger on board. Head to the destination!'))
  end)
end

local function finish()
  local o, p = online(), grnfr_nav.playerPos()
  if not (o and p) then return end
  busy = true
  local model, config = vehModel()
  local smoothness = comfortScore()
  local fn, args
  if job.kind == 'req' then
    fn, args = 'taxi_complete', { p_id = job.id, p_pos = grnfr_places.xyz(p), p_model_key = model, p_config_key = config, p_smoothness = smoothness }
  else
    fn, args = 'complete_job', { p_job = job.id, p_pos = grnfr_places.xyz(p), p_model_key = model, p_config_key = config, p_smoothness = smoothness }
  end
  o.call(fn, args, function(ok, data)
    busy = false
    if not job then return end
    if not ok then
      lastMsg = o.errText(data)
      if data == 'job_unavailable' or data == 'request_unavailable' then clearJob() else retry = 4 end
      return
    end
    local paid, tip = 0, 0
    if job.kind == 'npc' and type(data) == 'table' then
      paid, tip = tonumber(data.paid) or 0, tonumber(data.tip) or 0
      if data.capped then toast(L('Plafond de gains horaire atteint : gain réduit.', 'Hourly earnings cap reached: reduced payout.'), 'warning') end
    else
      paid = tonumber(data) or 0
    end
    earned, rides = earned + paid, rides + 1
    if job.kind == 'req' and paid <= 0 then
      toast(L('Course trop secouée : le passager a refusé de payer !', 'Ride too rough: the passenger refused to pay!'), 'error')
    elseif tip > 0 then
      toast(L('Course terminée : +', 'Ride complete: +') .. fmtMoney(paid) .. L(' (dont ', ' (incl. ') .. fmtMoney(tip) .. L(' de pourboire confort)', ' comfort tip)'), 'success')
    else
      toast(L('Course terminée : +', 'Ride complete: +') .. fmtMoney(paid), 'success')
    end
    slog('info', 'Taxi: ride completed (' .. job.kind .. '), smoothness ' .. smoothness .. '/100.')
    clearJob()
    cooldown = 8 -- laisse un peu de répit avant la prochaine course (demandé explicitement : pas de course collée juste après une dépose)
  end)
end

function M.setDuty(on)
  on = on == true
  local o = online()
  if on and not (o and o.isAuthed()) then toast(L('Connectez-vous d\'abord (touche O).', 'Sign in first (O key).'), 'warning') return false end
  if on == duty then return true end
  duty = on
  if not duty and job then
    if job.kind == 'req' then o.call('cancel_taxi_request', { p_id = job.id }) else o.call('cancel_job', { p_job = job.id }) end
    clearJob()
  end
  cooldown, retry, lastMsg = 3, 0, ''
  toast(duty and L('Vous êtes en service (taxi).', 'You are on duty (taxi).') or L('Fin de service.', 'Off duty.'))
  slog('info', 'Taxi duty ' .. (duty and 'ON' or 'OFF') .. '.')
  return true
end

function M.cancel()
  local o = online()
  if job and o then
    if job.kind == 'req' then o.call('cancel_taxi_request', { p_id = job.id }) else o.call('cancel_job', { p_job = job.id }) end
    clearJob()
    cooldown = 4
  end
  return true
end

function M.update(dt)
  if not duty then return end
  if job and job.phase == 'dropoff' then sampleComfort(dt) end
  if retry > 0 then retry = retry - dt return end
  if cooldown > 0 then cooldown = cooldown - dt return end
  if busy then return end
  if not job then newNpcFare() return end
  if job.phase == 'pickup' and grnfr_nav.arrived(4) then board()
  elseif job.phase == 'dropoff' and grnfr_nav.arrived(4) then finish() end
end

function M.status()
  local d = job and grnfr_nav.distance()
  return { duty = duty, busy = busy, kind = job and job.kind or nil, phase = job and job.phase or 'idle', fare = job and job.fare or 0,
           name = job and job.name or nil, dist = d and math.floor(d) or nil, earned = earned, rides = rides, msg = lastMsg,
           comfort = (job and job.phase == 'dropoff') and comfortScore() or nil }
end

function M.reset()
  duty, job, busy, cooldown, retry, lastMsg = false, nil, false, 0, 0, ''
  grnfr_nav.clear()
end

return M
