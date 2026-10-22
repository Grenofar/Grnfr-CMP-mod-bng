-- =====================================================================================
-- GRNFR Online - 0021 : salarié au garage (TODO "grand chantier" du 22/10/2026, Phase D).
-- Idée du joueur : "chaque 100 km je paie un salarié qui livre et qui rapporte." Interprété ainsi : une fois
-- embauché, le salarié travaille tout seul en arrière-plan tant qu'on est en ligne (pas besoin de conduire soi-
-- même) ; sa progression avance au temps réel écoulé (vitesse virtuelle fixe, `employee_speed_kmh`), jamais au
-- nombre de secondes ANNONCÉ par le client : employee_tick() mesure lui-même l'écart avec son propre horodatage
-- serveur (last_tick_at), plafonné par employee_max_tick_seconds (protège aussi contre une reconnexion après une
-- longue coupure). Toutes les 100 km accumulés, un "trajet" est payé automatiquement (revenu - salaire, toujours
-- décidé par le serveur via server_config, jamais par le client) -- même esprit que private.add_money partout
-- ailleurs : aucun montant ne vient du client.
-- À exécuter APRÈS 0001-0020.
-- =====================================================================================

insert into public.server_config (key, value, description) values
  ('employee_hire_cost',        '5000', 'Salarié : coût d''embauche (une fois)'),
  ('employee_speed_kmh',        '60',   'Salarié : vitesse virtuelle (km/h) utilisée pour faire avancer sa progression en temps réel'),
  ('employee_income_per_100km', '500',  'Salarié : revenu généré tous les 100 km parcourus'),
  ('employee_wage_per_100km',   '200',  'Salarié : salaire payé tous les 100 km parcourus (déduit du revenu ci-dessus)'),
  ('employee_max_tick_seconds', '120',  'Salarié : écart de temps réel maximum accepté par mise à jour (protège contre une longue coupure/reconnexion)')
on conflict (key) do nothing;

create table if not exists public.garage_employees (
  user_id           uuid primary key references public.profiles (id) on delete cascade,
  active            boolean not null default false,
  hired_at          timestamptz,
  distance_m        numeric not null default 0 check (distance_m >= 0),
  total_distance_m  numeric not null default 0 check (total_distance_m >= 0),
  total_earned      bigint not null default 0,
  last_tick_at      timestamptz not null default now()
);

create or replace function public.hire_employee() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_cost bigint := private.cfg('employee_hire_cost')::bigint;
  e public.garage_employees;
begin
  select * into e from public.garage_employees where user_id = v_me for update;
  if found and e.active then raise exception 'already_hired'; end if;
  perform private.add_money(v_me, -v_cost, 'employee_hire', null, 'Embauche d''un salarié');
  insert into public.garage_employees (user_id, active, hired_at, distance_m, last_tick_at)
  values (v_me, true, now(), 0, now())
  on conflict (user_id) do update set active = true, hired_at = now(), distance_m = 0, last_tick_at = now();
  return jsonb_build_object('active', true, 'distance_m', 0, 'total_distance_m',
    coalesce((select total_distance_m from public.garage_employees where user_id = v_me), 0),
    'total_earned', coalesce((select total_earned from public.garage_employees where user_id = v_me), 0));
end $$;

create or replace function public.fire_employee() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user();
begin
  update public.garage_employees set active = false where user_id = v_me;
  if not found then raise exception 'not_hired'; end if;
  return jsonb_build_object('active', false);
end $$;

create or replace function public.employee_status() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); e public.garage_employees;
begin
  select * into e from public.garage_employees where user_id = v_me;
  if not found then return jsonb_build_object('active', false, 'distance_m', 0, 'total_distance_m', 0, 'total_earned', 0); end if;
  return jsonb_build_object('active', e.active, 'distance_m', round(e.distance_m), 'total_distance_m', round(e.total_distance_m),
    'total_earned', e.total_earned);
end $$;

-- Appelée périodiquement (Lua) tant que le joueur est en ligne. N'accepte AUCUN paramètre du client : la durée
-- écoulée est mesurée côté serveur (now() - last_tick_at), plafonnée, pour qu'aucun montant ne dépende du client.
create or replace function public.employee_tick() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  e public.garage_employees;
  v_elapsed numeric;
  v_max numeric := private.cfg('employee_max_tick_seconds');
  v_speed numeric := private.cfg('employee_speed_kmh');
  v_income bigint := private.cfg('employee_income_per_100km')::bigint;
  v_wage bigint := private.cfg('employee_wage_per_100km')::bigint;
  v_net bigint := v_income - v_wage;
  v_trips int := 0;
  v_paid bigint := 0;
begin
  select * into e from public.garage_employees where user_id = v_me for update;
  if not found or not e.active then return jsonb_build_object('active', false); end if;
  v_elapsed := greatest(0, least(extract(epoch from (now() - e.last_tick_at)), v_max));
  e.distance_m := e.distance_m + v_elapsed * v_speed * 1000.0 / 3600.0;
  while e.distance_m >= 100000 and v_trips < 50 loop -- garde-fou : au plus 50 trajets payés par appel
    e.distance_m := e.distance_m - 100000;
    e.total_distance_m := e.total_distance_m + 100000;
    v_trips := v_trips + 1;
  end loop;
  if v_trips > 0 and v_net <> 0 then
    perform private.add_money(v_me, v_net * v_trips, 'employee_delivery', null,
      'Livraison automatique du salarié (+' || (v_trips * 100) || ' km)');
    v_paid := v_net * v_trips;
  end if;
  update public.garage_employees set distance_m = e.distance_m, total_distance_m = e.total_distance_m,
    total_earned = total_earned + v_paid, last_tick_at = now() where user_id = v_me;
  return jsonb_build_object('active', true, 'distance_m', round(e.distance_m), 'total_distance_m', round(e.total_distance_m),
    'trips', v_trips, 'paid', v_paid);
end $$;

-- ------------------------------------------------------------------ get_me() : ajoute l'état du salarié
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
                 from public.deliveries d where d.accepted_by = v_me and d.status = 'accepted' limit 1),
    'employee', (select jsonb_build_object('active', e.active, 'distance_m', round(e.distance_m),
                   'total_distance_m', round(e.total_distance_m), 'total_earned', e.total_earned)
                 from public.garage_employees e where e.user_id = v_me)
  ) into v_out;
  return v_out;
end $$;

-- ------------------------------------------------------------------ droits
alter table public.garage_employees enable row level security;
revoke all on public.garage_employees from anon, authenticated;
grant all privileges on public.garage_employees to postgres, service_role;
revoke all on function public.hire_employee(), public.fire_employee(), public.employee_status(), public.employee_tick()
  from public, anon, authenticated;
grant execute on function public.hire_employee(), public.fire_employee(), public.employee_status(), public.employee_tick()
  to authenticated;
