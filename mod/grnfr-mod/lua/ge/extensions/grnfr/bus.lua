-- GRNFR Online : ligne de bus. Le joueur conduit une boucle d'arrêts ; à chaque tronçon des passagers (nombre tiré par le
-- serveur) montent à un arrêt et descendent au suivant. Le gain est calculé et versé par le serveur (plafonné par heure).
-- Arrêts : points du réseau routier espacés de 600 à 1500 m (jamais en pleine nature).
local M = {}

local run = nil -- { stops = { {x,y,z,node,name} }, i = index de l'arrêt courant, phase = 'to_stop'|'dwell'|'to_next', job, dwell }
local busy, retry, lastMsg = false, 0, ''
local earned, legs = 0, 0
local STOPS = 5
local DWELL = 3 -- secondes d'arrêt pour « faire monter les passagers »

local function online() return rawget(_G, 'grnfr_online') end
local function L(fr, en) local o = online() return o and o.L(fr, en) or fr end
local function toast(m, k) local o = online() if o then o.toast(m, k) end end
local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

local function stopName(i) return L('Arrêt ', 'Stop ') .. tostring(i) end

local function buildStops(origin)
  local first = grnfr_places.randomNear(origin, 80, 500)
  if not first then return nil end
  local stops = { first }
  for _ = 2, STOPS do
    local n = grnfr_places.randomNear(stops[#stops], 600, 1500)
    if not n then break end
    stops[#stops + 1] = n
  end
  if #stops < 3 then return nil end
  for i, s in ipairs(stops) do s.name = stopName(i) end
  return stops
end

local function target(i)
  local s = run.stops[i]
  grnfr_nav.set(s.x, s.y, s.z, s.name, 30)
end

local function nextIndex(i) return i % #run.stops + 1 end

function M.start()
  local o = online()
  if not (o and o.isAuthed()) then toast(L('Connectez-vous d\'abord (touche O).', 'Sign in first (O key).'), 'warning') return false end
  if run then return true end
  local origin = grnfr_places.playerPos()
  local stops = origin and buildStops(origin)
  if not stops then toast(L('Impossible de tracer une ligne ici (pas assez de routes).', 'Could not build a route here (not enough roads).'), 'error') return false end
  run = { stops = stops, i = 1, phase = 'to_stop', dwell = 0 }
  busy, retry, lastMsg = false, 0, ''
  target(1)
  toast(L('Ligne de bus lancée : rendez-vous au premier arrêt.', 'Bus line started: go to the first stop.'))
  slog('info', 'Bus line started with ' .. #stops .. ' stops.')
  return true
end

function M.stop()
  if not run then return true end
  local o = online()
  if run.job and o then o.call('cancel_job', { p_job = run.job }) end
  run = nil
  busy = false
  grnfr_nav.clear()
  toast(L('Ligne de bus arrêtée.', 'Bus line stopped.'))
  return true
end

-- Au départ d'un arrêt : le serveur tire les passagers et fixe le gain, puis on embarque.
local function startLeg()
  local o = online()
  local a, b = run.stops[run.i], run.stops[nextIndex(run.i)]
  local route = grnfr_places.routeLength(a, b)
  busy = true
  o.call('start_job', { p_kind = 'bus_leg', p_level = grnfr_places.level(), p_pickup = grnfr_places.xyz(a),
    p_dropoff = grnfr_places.xyz(b), p_distance_m = route }, function(ok, data)
    if not run then busy = false return end
    if not ok then busy = false lastMsg = o.errText(data) retry = 6 return end
    local p = grnfr_nav.playerPos() or a
    o.call('board_job', { p_job = data.id, p_pos = grnfr_places.xyz(p) }, function(ok2, data2)
      busy = false
      if not run then return end
      if not ok2 then lastMsg = o.errText(data2) retry = 5 o.call('cancel_job', { p_job = data.id }) return end
      run.job, run.pax, run.fare = data.id, data.passengers, data.fare
      run.phase = 'to_next'
      target(nextIndex(run.i))
      toast(tostring(data.passengers) .. L(' passager(s) à bord. Direction ', ' passenger(s) on board. Next: ') .. run.stops[nextIndex(run.i)].name)
    end)
  end)
end

local function endLeg()
  local o = online()
  local p = grnfr_nav.playerPos()
  if not p then return end
  busy = true
  o.call('complete_job', { p_job = run.job, p_pos = grnfr_places.xyz(p) }, function(ok, data)
    busy = false
    if not run then return end
    if not ok then lastMsg = o.errText(data) retry = 4 if data == 'job_unavailable' then run.job, run.phase = nil, 'dwell' end return end
    local paid = type(data) == 'table' and tonumber(data.paid) or 0
    earned, legs = earned + paid, legs + 1
    if type(data) == 'table' and data.capped then toast(L('Plafond de gains horaire atteint : gain réduit.', 'Hourly earnings cap reached: reduced payout.'), 'warning') end
    toast(L('Arrêt desservi : +$', 'Stop served: +$') .. tostring(paid), 'success')
    run.i, run.job, run.phase, run.dwell = nextIndex(run.i), nil, 'dwell', 0
  end)
end

function M.update(dt)
  if not run or busy then return end
  if retry > 0 then retry = retry - dt return end
  if run.phase == 'to_stop' then
    if grnfr_nav.arrived(4) then run.phase, run.dwell = 'dwell', 0 end
  elseif run.phase == 'dwell' then
    if grnfr_nav.playerSpeed() > 6 then return end -- on repart sans attendre : le temps d'arrêt recommence
    run.dwell = run.dwell + dt
    if run.dwell >= DWELL then startLeg() end
  elseif run.phase == 'to_next' then
    if grnfr_nav.arrived(4) then endLeg() end
  end
end

function M.status()
  local d = run and grnfr_nav.get() and grnfr_nav.distance()
  return { active = run ~= nil, phase = run and run.phase or 'idle', stop = run and run.i or 0, stops = run and #run.stops or 0,
           passengers = run and run.pax or 0, earned = earned, legs = legs, dist = d and math.floor(d) or nil, msg = lastMsg }
end

function M.reset() run, busy, retry, lastMsg = nil, false, 0, '' grnfr_nav.clear() end

return M
