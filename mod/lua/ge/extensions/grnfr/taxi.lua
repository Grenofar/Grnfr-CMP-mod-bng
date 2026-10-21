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
    grnfr_nav.set(job.dropoff.x, job.dropoff.y, job.dropoff.z or 0, L('Destination', 'Destination'), 35)
    toast(L('Passager à bord. Direction la destination !', 'Passenger on board. Head to the destination!'))
  end)
end

local function finish()
  local o, p = online(), grnfr_nav.playerPos()
  if not (o and p) then return end
  busy = true
  local fn, args
  if job.kind == 'req' then fn, args = 'taxi_complete', { p_id = job.id, p_pos = grnfr_places.xyz(p) }
  else fn, args = 'complete_job', { p_job = job.id, p_pos = grnfr_places.xyz(p) } end
  o.call(fn, args, function(ok, data)
    busy = false
    if not job then return end
    if not ok then
      lastMsg = o.errText(data)
      if data == 'job_unavailable' or data == 'request_unavailable' then clearJob() else retry = 4 end
      return
    end
    local paid = 0
    if job.kind == 'npc' and type(data) == 'table' then paid = tonumber(data.paid) or 0
      if data.capped then toast(L('Plafond de gains horaire atteint : gain réduit.', 'Hourly earnings cap reached: reduced payout.'), 'warning') end
    else paid = job.fare end
    earned, rides = earned + paid, rides + 1
    toast(L('Course terminée : +', 'Ride complete: +') .. fmtMoney(paid), 'success')
    slog('info', 'Taxi: ride completed (' .. job.kind .. ').')
    clearJob()
    cooldown = 4
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
           name = job and job.name or nil, dist = d and math.floor(d) or nil, earned = earned, rides = rides, msg = lastMsg }
end

function M.reset()
  duty, job, busy, cooldown, retry, lastMsg = false, nil, false, 0, 0, ''
  grnfr_nav.clear()
end

return M
