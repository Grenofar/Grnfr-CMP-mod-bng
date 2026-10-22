-- =====================================================================================
-- GRNFR Online - 0016 : livraisons de colis comme la carrière, en multijoueur (TODO phase 2, premier morceau).
-- À exécuter APRÈS 0001-0015.
--
-- Les points de ramassage/dépôt réels (deliveryProvider de la carte) ne sont connus que du jeu (Lua) : le serveur
-- ne peut pas générer de vraies positions tout seul. Le mod (grnfr/delivery.lua) lit les vrais points de la carte
-- et propose des paires au serveur (generate_deliveries), qui recalcule LUI-MÊME la distance (private.route_length,
-- comme pour le taxi/bus) et le prix — jamais un prix envoyé par le client. Nouvelle table séparée de `jobs` (celle-ci
-- reste pour le taxi/bus existant) car une livraison est partagée tant que personne ne l'a acceptée (pas de
-- propriétaire au départ), alors que `jobs` appartient toujours à un joueur dès la création.
-- Cycle : generate_deliveries (Lua) -> list_deliveries -> accept_delivery (vérifie la capacité cargo du véhicule,
-- 0015_vehicle_customization.sql) -> complete_delivery (position + durée crédible, comme complete_job) ou
-- cancel_delivery (remise à disposition pour un autre joueur).
-- =====================================================================================

insert into public.server_config (key, value, description) values
  ('delivery_base_fare',             '40',  'Livraison : prise en charge'),
  ('delivery_per_km',                '4',   'Livraison : prix au km'),
  ('delivery_per_unit',               '15',  'Livraison : prix par unité de capacité cargo demandée'),
  ('delivery_max_active_per_level',  '15',  'Livraison : nombre maximum d''offres disponibles en même temps par carte'),
  ('delivery_offer_ttl_minutes',     '30',  'Livraison : durée de vie d''une offre non acceptée (minutes)')
on conflict (key) do nothing;

create table if not exists public.deliveries (
  id           uuid primary key default gen_random_uuid(),
  level        text not null,
  pickup       jsonb not null,
  dropoff      jsonb not null,
  client_name  text,
  route_m      int not null,
  cargo_units  int not null default 1 check (cargo_units between 1 and 10),
  fare         bigint not null check (fare >= 0),
  min_seconds  int not null,
  status       text not null default 'available' check (status in ('available', 'accepted', 'delivered', 'cancelled', 'expired')),
  accepted_by  uuid references public.profiles (id) on delete set null,
  vehicle_id   uuid references public.garage_vehicles (id) on delete set null,
  created_at   timestamptz not null default now(),
  accepted_at  timestamptz,
  delivered_at timestamptz,
  expires_at   timestamptz not null
);
create index if not exists deliveries_level_status on public.deliveries (level, status);
create index if not exists deliveries_accepted_by on public.deliveries (accepted_by) where accepted_by is not null;

-- Les gains de livraison comptent désormais dans le même plafond horaire que le taxi PNJ / bus (anti-triche).
create or replace function private.capped_income(p_user uuid, p_amount bigint, p_kind text, p_ref text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_cap  bigint := private.cfg('npc_income_cap_per_hour')::bigint;
  v_used bigint;
  v_pay  bigint;
begin
  select coalesce(sum(amount), 0) into v_used from public.transactions
   where user_id = p_user and kind in ('npc_taxi', 'bus', 'delivery') and created_at > now() - interval '1 hour';
  v_pay := greatest(least(p_amount, v_cap - v_used), 0);
  if v_pay > 0 then perform private.add_money(p_user, v_pay, p_kind, null, p_ref); end if;
  return jsonb_build_object('paid', v_pay, 'asked', p_amount, 'capped', v_pay < p_amount);
end $$;

-- Expire aussi les offres/livraisons en cours trop vieilles (comme pour taxi_requests/jobs).
create or replace function private.expire_stale() returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare r record;
begin
  for r in select id, passenger_id, fare from public.taxi_requests
            where status = 'requested' and expires_at < now() for update skip locked loop
    update public.taxi_requests set status = 'expired' where id = r.id;
    perform private.add_money(r.passenger_id, r.fare, 'taxi_refund', null, 'Demande expirée');
  end loop;
  for r in select id, user_id, kind, fare, status from public.jobs
            where status in ('started', 'boarded') and expires_at < now() for update skip locked loop
    update public.jobs set status = 'expired', finished_at = now() where id = r.id;
    if r.kind = 'bot_taxi' and r.status = 'started' then
      perform private.add_money(r.user_id, r.fare, 'taxi_refund', null, 'Taxi IA expiré');
    end if;
  end loop;
  update public.deliveries set status = 'expired' where status in ('available', 'accepted') and expires_at < now();
end $$;

-- p_offers = [{ pickup:{x,y,z,name}, dropoff:{x,y,z,name}, distance_m, units, client_name }, ...] proposé par le Lua
-- (vrais points deliveryProvider de la carte). Renvoie le nombre d'offres effectivement ajoutées.
create or replace function public.generate_deliveries(p_level text, p_offers jsonb) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_max int := private.cfg('delivery_max_active_per_level')::int;
  v_ttl int := private.cfg('delivery_offer_ttl_minutes')::int;
  o jsonb; v_cur int; v_route int; v_km numeric; v_fare bigint; v_units int; v_added int := 0;
begin
  perform private.expire_stale();
  if coalesce(p_level, '') = '' or jsonb_typeof(p_offers) is distinct from 'array' then raise exception 'bad_args'; end if;
  select count(*) into v_cur from public.deliveries where level = left(p_level, 60) and status = 'available' and expires_at > now();
  for o in select * from jsonb_array_elements(p_offers) loop
    if v_cur + v_added >= v_max then exit; end if;
    if private.valid_pos(o -> 'pickup') and private.valid_pos(o -> 'dropoff') and private.dist(o -> 'pickup', o -> 'dropoff') >= 150 then
      v_units := greatest(1, least(10, coalesce((o ->> 'units')::int, 1)));
      v_route := private.route_length(o -> 'pickup', o -> 'dropoff', (o ->> 'distance_m')::int);
      v_km := v_route / 1000.0;
      v_fare := round(private.cfg('delivery_base_fare') + private.cfg('delivery_per_km') * v_km + private.cfg('delivery_per_unit') * v_units);
      insert into public.deliveries (level, pickup, dropoff, client_name, route_m, cargo_units, fare, min_seconds, expires_at)
      values (left(p_level, 60), private.clean_pos(o -> 'pickup'), private.clean_pos(o -> 'dropoff'), left(o ->> 'client_name', 40),
              v_route, v_units, v_fare, ceil(v_route / private.cfg('max_speed_mps')), now() + (v_ttl || ' minutes')::interval);
      v_added := v_added + 1;
    end if;
  end loop;
  return v_added;
end $$;

create or replace function public.list_deliveries(p_level text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'pickup', pickup, 'dropoff', dropoff, 'client_name', client_name,
           'route_m', route_m, 'cargo_units', cargo_units, 'fare', fare) order by created_at), '[]'::jsonb)
    from public.deliveries
   where level = left(coalesce(p_level, ''), 60) and status = 'available' and expires_at > now() $$;

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
    'cargo_units', d.cargo_units, 'min_seconds', d.min_seconds, 'client_name', d.client_name);
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
  v_res := private.capped_income(v_me, d.fare, 'delivery', 'Livraison' || case when d.client_name is not null then ' : ' || d.client_name else '' end);
  return v_res;
end $$;

-- Remise à disposition pour un autre joueur (pas de pénalité, pas d'argent en jeu avant la livraison).
create or replace function public.cancel_delivery(p_delivery_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_n int;
begin
  update public.deliveries set status = 'available', accepted_by = null, vehicle_id = null, accepted_at = null
   where id = p_delivery_id and accepted_by = v_me and status = 'accepted';
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'job_unavailable'; end if;
end $$;

-- ------------------------------------------------------------------ get_me : + livraison en cours
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
    'delivery', (select jsonb_build_object('id', d.id, 'pickup', d.pickup, 'dropoff', d.dropoff, 'client_name', d.client_name,
                   'route_m', d.route_m, 'cargo_units', d.cargo_units, 'fare', d.fare, 'vehicle_id', d.vehicle_id)
                 from public.deliveries d where d.accepted_by = v_me and d.status = 'accepted' limit 1)
  ) into v_out;
  return v_out;
end $$;

-- ------------------------------------------------------------------ droits
alter table public.deliveries enable row level security;
revoke all on public.deliveries from anon, authenticated;
grant all privileges on public.deliveries to postgres, service_role;
revoke all on function public.generate_deliveries(text, jsonb), public.list_deliveries(text),
  public.accept_delivery(uuid, uuid), public.complete_delivery(uuid, jsonb), public.cancel_delivery(uuid), public.get_me()
  from public, anon, authenticated;
grant execute on function public.generate_deliveries(text, jsonb), public.list_deliveries(text),
  public.accept_delivery(uuid, uuid), public.complete_delivery(uuid, jsonb), public.cancel_delivery(uuid), public.get_me()
  to authenticated;
