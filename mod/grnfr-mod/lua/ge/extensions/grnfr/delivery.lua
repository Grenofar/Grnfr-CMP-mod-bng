-- GRNFR Online : livraisons de colis comme la carrière, en multijoueur (TODO phase 2, premier morceau).
--
-- Déroulé : M.refresh() lit les vrais points de livraison de la carte (grnfr_facilities.deliveryPoints(), API
-- getFacilitiesByType('deliveryProvider') non vérifiée en jeu) et propose des paires au serveur, qui recalcule
-- lui-même la distance/le prix (supabase/migrations/0016_deliveries.sql, jamais un prix côté client) -> la liste
-- publiée est renvoyée. M.accept(id, vehicleId) réserve une livraison (le serveur vérifie la capacité cargo du
-- véhicule, 0015), guide (grnfr_nav, comme taxi.lua) d'abord vers le ramassage puis la livraison, et appelle le
-- serveur à l'arrivée (position + durée crédible, comme complete_job). Même philosophie que taxi.lua : le jeu ne
-- décide jamais d'un montant, et une seule livraison active à la fois par joueur (imposé aussi côté serveur).
local M = {}

-- Entreprises variées (demandé explicitement) : l'envoyeur et le destinataire sont tirés indépendamment de
-- cette liste, jamais la même pour les deux dans une offre (voir buildOffers).
local COMPANIES = {
  'Resto Chez Mario', 'Pizzeria Luna', 'Café du Port', 'Garage Fontaine', 'Garage Rapido',
  'Hôpital Sainte-Anne', 'Clinique du Nord', 'Pharmacie Centrale', 'Quick Parcel', 'Metro Logistics',
  'FastFreight', 'ValleyGoods', 'Harbor Supplies', 'Coastline Cargo', 'Épicerie Bellevue', 'Hôtel Riviera',
}

local job = nil   -- { id, pickup={x,y,z,name}, dropoff={x,y,z,name}, senderName, recipientName, fare, units, weightKg, vehicleId, phase='pickup'|'dropoff' }
local busy = false
local offers = {} -- dernière liste reçue de list_deliveries
local lastMsg = ''
local earned, deliveries = 0, 0

local function online() return rawget(_G, 'grnfr_online') end
local function L(fr, en) local o = online() return o and o.L(fr, en) or fr end
local function toast(m, k) local o = online() if o then o.toast(m, k) end end
local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local function fmtMoney(n) return '$' .. tostring(math.floor(tonumber(n) or 0)) end

-- Construit jusqu'à `max` offres candidates à partir des vrais points de livraison de la carte (jamais au hasard
-- sur la route) : paires différentes, à au moins 150 m (minimum accepté par le serveur).
local function buildOffers(max)
  local pts = grnfr_facilities.deliveryPoints()
  local out = {}
  if #pts < 2 then return out end
  local tries = 0
  while #out < max and tries < max * 8 do
    tries = tries + 1
    local a = pts[math.random(#pts)]
    local b = pts[math.random(#pts)]
    if a ~= b then
      local d = grnfr_facilities.dist(a.pos, b.pos)
      if d >= 150 then
        local units = 1 + math.random(0, 2)
        local sender = COMPANIES[math.random(#COMPANIES)]
        local recipient = sender
        for _ = 1, 6 do recipient = COMPANIES[math.random(#COMPANIES)] if recipient ~= sender then break end end
        out[#out + 1] = {
          pickup = { x = a.pos.x, y = a.pos.y, z = a.pos.z, name = a.name },
          dropoff = { x = b.pos.x, y = b.pos.y, z = b.pos.z, name = b.name },
          distance_m = math.floor(d),
          units = units,
          weight_kg = units * (15 + math.random(0, 25)), -- ~15 à 40 kg par unité de capacité demandée
          sender_name = sender,
          recipient_name = recipient,
        }
      end
    end
  end
  return out
end

-- Demande au serveur de publier de nouvelles offres (si la carte a de vrais points de livraison), puis renvoie la
-- liste à jour. cb(ok, offres_ou_code_erreur).
function M.refresh(cb)
  local o = online()
  if not (o and o.isAuthed()) then if cb then cb(false, 'not_authenticated') end return end
  local level = grnfr_places.level()
  local function list()
    o.call('list_deliveries', { p_level = level }, function(ok, data)
      if ok then offers = type(data) == 'table' and data or {} end
      if cb then cb(ok, ok and offers or data) end
    end)
  end
  local candidates = buildOffers(6)
  if #candidates > 0 then o.call('generate_deliveries', { p_level = level, p_offers = candidates }, function() list() end)
  else list() end
end

function M.offers() return offers end

function M.accept(id, vehicleId, cb)
  local o = online()
  if not (o and o.isAuthed()) then if cb then cb(false, 'not_authenticated') end return end
  if job then toast(L('Une livraison est déjà en cours.', 'A delivery is already in progress.'), 'warning') if cb then cb(false, 'already_active') end return end
  busy = true
  o.call('accept_delivery', { p_delivery_id = id, p_vehicle_id = vehicleId }, function(ok, data)
    busy = false
    if not ok then if cb then cb(false, data) end return end
    job = { id = data.id, pickup = data.pickup, dropoff = data.dropoff, senderName = data.sender_name,
      recipientName = data.recipient_name, fare = data.fare, units = data.cargo_units, weightKg = data.weight_kg,
      vehicleId = vehicleId, phase = 'pickup' }
    grnfr_nav.set(job.pickup.x, job.pickup.y, job.pickup.z or 0, job.pickup.name or L('Ramassage', 'Pickup'), 25)
    toast(L('Livraison acceptée pour ', 'Delivery accepted for ') .. tostring(job.recipientName or '?')
      .. L(' : récupérez le colis chez ', ': pick up the parcel at ') .. tostring(job.senderName or '?') .. '.')
    slog('info', 'Delivery: accepted (' .. fmtMoney(job.fare) .. ').')
    if cb then cb(true, job) end
  end)
end

function M.cancel()
  local o = online()
  if job and o then o.call('cancel_delivery', { p_delivery_id = job.id }) end
  job, busy = nil, false
  grnfr_nav.clear()
  return true
end

local function finish()
  local o, p = online(), grnfr_nav.playerPos()
  if not (o and p) then return end
  busy = true
  o.call('complete_delivery', { p_delivery_id = job.id, p_pos = grnfr_places.xyz(p) }, function(ok, data)
    busy = false
    if not job then return end
    if not ok then
      lastMsg = o.errText(data)
      if data == 'job_unavailable' then job = nil grnfr_nav.clear() end
      return
    end
    local paid = type(data) == 'table' and (tonumber(data.paid) or 0) or job.fare
    earned, deliveries = earned + paid, deliveries + 1
    toast(L('Livraison terminée : +', 'Delivery complete: +') .. fmtMoney(paid), 'success')
    slog('info', 'Delivery: completed.')
    job = nil
    grnfr_nav.clear()
  end)
end

function M.update(dt)
  if not job or busy then return end
  if job.phase == 'pickup' and grnfr_nav.arrived(5) then
    job.phase = 'dropoff'
    grnfr_nav.set(job.dropoff.x, job.dropoff.y, job.dropoff.z or 0, job.dropoff.name or L('Livraison', 'Drop-off'), 25)
    toast(L('Colis chargé. Direction le point de livraison (marqueur orange).', 'Cargo loaded. Head to the drop-off point (orange marker).'))
    slog('info', 'Delivery: picked up, heading to drop-off.')
  elseif job.phase == 'dropoff' and grnfr_nav.arrived(5) then
    finish()
  end
end

function M.status()
  local d = job and grnfr_nav.distance()
  return { active = job ~= nil, phase = job and job.phase or nil, fare = job and job.fare or 0, units = job and job.units or nil,
           weightKg = job and job.weightKg or nil, senderName = job and job.senderName or nil,
           recipientName = job and job.recipientName or nil, dist = d and math.floor(d) or nil, earned = earned,
           deliveries = deliveries, msg = lastMsg, busy = busy }
end

function M.reset()
  job, busy, offers, lastMsg = nil, false, {}, ''
  grnfr_nav.clear()
end

return M
