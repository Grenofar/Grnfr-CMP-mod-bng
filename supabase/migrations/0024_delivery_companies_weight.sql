-- =====================================================================================
-- GRNFR Online - 0024 : livraisons entre entreprises, prix au poids (grand chantier Phase D, reste à faire).
-- Demande du joueur : "fais plusieurs entreprises, genre resto/garage/hôpital, pour livrer, récupérer de
-- l'envoyeur et donner au destinataire, le prix varie entre le poids et la distance". `client_name` (0016)
-- devient le nom de l'ENVOYEUR (sender_name, rétrocompatible : même colonne), nouvelle colonne pour le
-- DESTINATAIRE (recipient_name). Le poids (weight_kg) remplace cargo_units comme base du calcul de prix — mais
-- cargo_units reste la condition de capacité (garage_vehicles.cargo_capacity), inchangée. Toujours : le Lua
-- propose une paire de points réels de la carte + un poids plausible, le serveur recalcule TOUT lui-même
-- (distance via private.route_length comme avant, prix via les nouveaux server_config ci-dessous) — jamais un
-- prix envoyé par le client.
-- À exécuter APRÈS 0001-0023.
-- =====================================================================================

alter table public.deliveries rename column client_name to sender_name;
alter table public.deliveries add column if not exists recipient_name text;
alter table public.deliveries add column if not exists weight_kg int not null default 20 check (weight_kg > 0);

insert into public.server_config (key, value, description) values
  ('delivery_per_kg', '0.3', 'Livraison : prix au kg de marchandise (remplace le prix par unité de capacité pour le calcul du prix)')
on conflict (key) do nothing;

create or replace function public.generate_deliveries(p_level text, p_offers jsonb) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_max int := private.cfg('delivery_max_active_per_level')::int;
  v_ttl int := private.cfg('delivery_offer_ttl_minutes')::int;
  o jsonb; v_cur int; v_route int; v_km numeric; v_fare bigint; v_units int; v_weight int; v_added int := 0;
begin
  perform private.expire_stale();
  if coalesce(p_level, '') = '' or jsonb_typeof(p_offers) is distinct from 'array' then raise exception 'bad_args'; end if;
  select count(*) into v_cur from public.deliveries where level = left(p_level, 60) and status = 'available' and expires_at > now();
  for o in select * from jsonb_array_elements(p_offers) loop
    if v_cur + v_added >= v_max then exit; end if;
    if private.valid_pos(o -> 'pickup') and private.valid_pos(o -> 'dropoff') and private.dist(o -> 'pickup', o -> 'dropoff') >= 150 then
      v_units := greatest(1, least(10, coalesce((o ->> 'units')::int, 1)));
      v_weight := greatest(1, least(2000, coalesce((o ->> 'weight_kg')::int, v_units * 25)));
      v_route := private.route_length(o -> 'pickup', o -> 'dropoff', (o ->> 'distance_m')::int);
      v_km := v_route / 1000.0;
      v_fare := round(private.cfg('delivery_base_fare') + private.cfg('delivery_per_km') * v_km + private.cfg('delivery_per_kg') * v_weight);
      insert into public.deliveries (level, pickup, dropoff, sender_name, recipient_name, route_m, cargo_units, weight_kg, fare, min_seconds, expires_at)
      values (left(p_level, 60), private.clean_pos(o -> 'pickup'), private.clean_pos(o -> 'dropoff'), left(o ->> 'sender_name', 40),
              left(o ->> 'recipient_name', 40), v_route, v_units, v_weight, v_fare, ceil(v_route / private.cfg('max_speed_mps')),
              now() + (v_ttl || ' minutes')::interval);
      v_added := v_added + 1;
    end if;
  end loop;
  return v_added;
end $$;

create or replace function public.accept_delivery(p_delivery_id uuid, p_vehicle_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); d public.deliveries; v_cap int;
begin
  perform private.expire_stale();
  if exists (select 1 from public.deliveries where accepted_by = v_me and status = 'accepted') then raise exception 'already_active'; end if;
  select * into d from public.deliveries where id = p_delivery_id for update;
  if not found or d.status <> 'available' or d.expires_at <= now() then raise exception 'job_unavailable'; end if;
  select cargo_capacity into v_cap from public.garage_vehicles where id = p_vehicle_id and owner_id = v_me;
  if v_cap is null then raise exception 'not_found'; end if;
  if v_cap < d.cargo_units then raise exception 'cargo_too_small'; end if;
  update public.deliveries set status = 'accepted', accepted_by = v_me, vehicle_id = p_vehicle_id, accepted_at = now() where id = d.id;
  return jsonb_build_object('id', d.id, 'pickup', d.pickup, 'dropoff', d.dropoff, 'fare', d.fare, 'route_m', d.route_m,
    'cargo_units', d.cargo_units, 'weight_kg', d.weight_kg, 'min_seconds', d.min_seconds,
    'sender_name', d.sender_name, 'recipient_name', d.recipient_name);
end $$;

create or replace function public.complete_delivery(p_delivery_id uuid, p_pos jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); d public.deliveries; v_res jsonb;
begin
  if not private.valid_pos(p_pos) then raise exception 'bad_position'; end if;
  select * into d from public.deliveries where id = p_delivery_id and accepted_by = v_me for update;
  if not found or d.status <> 'accepted' then raise exception 'job_unavailable'; end if;
  if private.dist(p_pos, d.dropoff) > 150 then raise exception 'too_far'; end if;
  if extract(epoch from (now() - d.accepted_at)) < d.min_seconds then raise exception 'too_fast'; end if;
  update public.deliveries set status = 'delivered', delivered_at = now() where id = d.id;
  v_res := private.capped_income(v_me, d.fare, 'delivery', 'Livraison'
    || case when d.sender_name is not null then ' de ' || d.sender_name else '' end
    || case when d.recipient_name is not null then ' pour ' || d.recipient_name else '' end);
  return v_res;
end $$;

create or replace function public.list_deliveries(p_level text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'pickup', pickup, 'dropoff', dropoff, 'sender_name', sender_name,
           'recipient_name', recipient_name, 'route_m', route_m, 'cargo_units', cargo_units, 'weight_kg', weight_kg, 'fare', fare)
           order by created_at), '[]'::jsonb)
    from public.deliveries
   where level = left(coalesce(p_level, ''), 60) and status = 'available' and expires_at > now() $$;

-- get_me() : le champ 'delivery' (0016/0021) expose maintenant aussi sender_name/recipient_name/weight_kg.
create or replace function public.get_me() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_out jsonb;
begin
  perform private.expire_stale();
  select jsonb_build_object(
    'profile', (select jsonb_build_object('id', p.id, 'username', p.username, 'balance', p.balance,
                  'is_admin', p.is_admin, 'garage_slots', p.garage_slots, 'duty', p.duty,
                  'lifetime_earned', p.lifetime_earned, 'username_confirmed', p.username_confirmed)
                from public.profiles p where p.id = v_me),
    'vehicles', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'slot', g.slot, 'model_key', g.model_key,
                  'config_key', g.config_key, 'color', g.color, 'nickname', g.nickname, 'value', g.value, 'insurance', g.insurance,
                  'parts', g.parts, 'tuning', g.tuning, 'paint', g.paint, 'cargo_capacity', g.cargo_capacity,
                  'perf_class', g.perf_class, 'comfort_class', g.comfort_class,
                  'listed', exists (select 1 from public.listings l where l.vehicle_id = g.id and l.status = 'open'))
                  order by g.slot) from public.garage_vehicles g where g.owner_id = v_me), '[]'::jsonb),
    'config', (select jsonb_object_agg(key, value) from public.server_config),
    'trades_in', coalesce((select jsonb_agg(t.id) from public.trades t where t.target_id = v_me and t.status = 'pending'), '[]'::jsonb),
    'trades_out', coalesce((select jsonb_agg(t.id) from public.trades t where t.proposer_id = v_me and t.status = 'pending'), '[]'::jsonb),
    'taxi', (select to_jsonb(x) from (
        select r.id, r.status, r.level, r.pickup, r.dropoff, r.route_m, r.fare,
               case when r.passenger_id = v_me then 'passenger' else 'driver' end as role,
               pp.username as passenger, dp.username as driver, dp.pos as driver_pos
          from public.taxi_requests r
          join public.profiles pp on pp.id = r.passenger_id
          left join public.profiles dp on dp.id = r.driver_id
         where (r.passenger_id = v_me or r.driver_id = v_me) and r.status in ('requested', 'accepted', 'picked_up')
         order by r.created_at desc limit 1) x),
    'delivery', (select jsonb_build_object('id', d.id, 'pickup', d.pickup, 'dropoff', d.dropoff, 'sender_name', d.sender_name,
                   'recipient_name', d.recipient_name, 'route_m', d.route_m, 'cargo_units', d.cargo_units, 'weight_kg', d.weight_kg,
                   'fare', d.fare, 'vehicle_id', d.vehicle_id)
                 from public.deliveries d where d.accepted_by = v_me and d.status = 'accepted' limit 1),
    'employee', private.employee_view(v_me)
  ) into v_out;
  return v_out;
end $$;
