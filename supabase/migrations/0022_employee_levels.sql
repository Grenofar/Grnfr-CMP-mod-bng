-- =====================================================================================
-- GRNFR Online - 0022 : niveaux de salarié (demandé juste après 0021 : "des niveaux de salarié, argent par
-- 100 km (obligé d'être gagnant mais ça peut être [variable])"). Deux changements par rapport à 0021 :
--   1. Plusieurs niveaux de salarié, achetables l'un après l'autre (upgrade_employee), chacun avec son propre
--      salaire et une FOURCHETTE de revenu par 100 km au lieu d'un montant fixe.
--   2. Le revenu par trajet de 100 km est tiré au hasard dans cette fourchette : à bas niveau, la fourchette
--      descend sous le salaire (perte nette possible) -- "pas obligé d'être gagnant", comme demandé. Les
--      niveaux supérieurs ont une fourchette qui monte plus haut en moyenne, sans jamais garantir un gain non
--      plus (toujours une petite chance de perte, pour que ça reste un vrai pari et pas un revenu passif sûr).
-- Les anciennes clés server_config `employee_hire_cost`/`employee_income_per_100km`/`employee_wage_per_100km`
-- (0021) ne sont plus lues (remplacées par la table employee_levels ci-dessous) ; laissées inertes dans
-- server_config plutôt que supprimées (pas de drop sur une migration déjà appliquée).
-- À exécuter APRÈS 0001-0021.
-- =====================================================================================

create table if not exists public.employee_levels (
  level             int primary key,
  label             text not null,
  upgrade_cost      bigint not null check (upgrade_cost >= 0), -- coût pour ATTEINDRE ce niveau depuis le précédent (ou embauche, pour le niveau 1)
  wage_per_100km    bigint not null check (wage_per_100km >= 0),
  income_min_100km  bigint not null,
  income_max_100km  bigint not null check (income_max_100km >= income_min_100km)
);

insert into public.employee_levels (level, label, upgrade_cost, wage_per_100km, income_min_100km, income_max_100km) values
  (1, 'Débutant',  5000,   200, 100,  500),
  (2, 'Confirmé',  15000,  300, 250,  700),
  (3, 'Expert',    40000,  450, 400, 1000),
  (4, 'Élite',     100000, 650, 600, 1500)
on conflict (level) do nothing;

alter table public.employee_levels enable row level security;
create policy employee_levels_read on public.employee_levels for select to anon, authenticated using (true);
grant select on public.employee_levels to anon, authenticated;

alter table public.garage_employees add column if not exists level int not null default 1 references public.employee_levels (level);

create or replace function public.hire_employee() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_cost bigint;
  e public.garage_employees;
begin
  select upgrade_cost into v_cost from public.employee_levels where level = 1;
  select * into e from public.garage_employees where user_id = v_me for update;
  if found and e.active then raise exception 'already_hired'; end if;
  perform private.add_money(v_me, -v_cost, 'employee_hire', null, 'Embauche d''un salarié (Débutant)');
  insert into public.garage_employees (user_id, active, hired_at, level, distance_m, last_tick_at)
  values (v_me, true, now(), 1, 0, now())
  on conflict (user_id) do update set active = true, hired_at = now(), level = 1, distance_m = 0, last_tick_at = now();
  return jsonb_build_object('active', true, 'level', 1, 'distance_m', 0, 'total_distance_m', 0, 'total_earned', 0);
end $$;

-- Fait passer le salarié actuel au niveau suivant (doit déjà être embauché). Coût = employee_levels.upgrade_cost
-- du niveau visé, toujours décidé par le serveur.
create or replace function public.upgrade_employee() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  e public.garage_employees;
  v_next int;
  v_cost bigint;
  v_label text;
begin
  select * into e from public.garage_employees where user_id = v_me for update;
  if not found or not e.active then raise exception 'not_hired'; end if;
  v_next := e.level + 1;
  select upgrade_cost, label into v_cost, v_label from public.employee_levels where level = v_next;
  if v_cost is null then raise exception 'max_level'; end if;
  perform private.add_money(v_me, -v_cost, 'employee_upgrade', null, 'Salarié promu : ' || v_label);
  update public.garage_employees set level = v_next where user_id = v_me;
  return jsonb_build_object('active', true, 'level', v_next);
end $$;

-- Construit le champ 'employee' complet (utilisé par get_me() et employee_status()) : état actuel + le niveau
-- "suivant" (à embaucher si pas encore de salarié, ou à promouvoir sinon) avec son coût, pour que l'UI n'ait
-- jamais besoin d'interroger la table employee_levels elle-même.
create or replace function private.employee_view(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare e public.garage_employees; cur public.employee_levels; nxt public.employee_levels;
begin
  select * into e from public.garage_employees where user_id = p_user;
  if not found or not e.active then
    select * into nxt from public.employee_levels where level = 1;
    return jsonb_build_object('active', false, 'level', 0, 'distance_m', 0, 'total_distance_m', 0, 'total_earned', 0,
      'next', jsonb_build_object('level', nxt.level, 'label', nxt.label, 'upgrade_cost', nxt.upgrade_cost));
  end if;
  select * into cur from public.employee_levels where level = e.level;
  select * into nxt from public.employee_levels where level = e.level + 1;
  return jsonb_build_object('active', true, 'level', e.level, 'level_label', cur.label,
    'distance_m', round(e.distance_m), 'total_distance_m', round(e.total_distance_m), 'total_earned', e.total_earned,
    'wage_per_100km', cur.wage_per_100km, 'income_min_100km', cur.income_min_100km, 'income_max_100km', cur.income_max_100km,
    'next', case when nxt.level is null then null else
      jsonb_build_object('level', nxt.level, 'label', nxt.label, 'upgrade_cost', nxt.upgrade_cost) end);
end $$;

create or replace function public.employee_status() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user();
begin
  return private.employee_view(v_me);
end $$;

-- Appelée périodiquement (Lua) tant que le joueur est en ligne. Toujours AUCUN paramètre du client : durée
-- écoulée mesurée côté serveur, revenu par trajet tiré au hasard dans la fourchette du niveau actuel.
create or replace function public.employee_tick() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  e public.garage_employees;
  lvl public.employee_levels;
  v_elapsed numeric;
  v_max numeric := private.cfg('employee_max_tick_seconds');
  v_trips int := 0;
  v_paid bigint := 0;
  v_income bigint;
begin
  select * into e from public.garage_employees where user_id = v_me for update;
  if not found or not e.active then return jsonb_build_object('active', false); end if;
  select * into lvl from public.employee_levels where level = e.level;
  v_elapsed := greatest(0, least(extract(epoch from (now() - e.last_tick_at)), v_max));
  e.distance_m := e.distance_m + v_elapsed * private.cfg('employee_speed_kmh') * 1000.0 / 3600.0;
  while e.distance_m >= 100000 and v_trips < 50 loop -- garde-fou : au plus 50 trajets payés par appel
    e.distance_m := e.distance_m - 100000;
    e.total_distance_m := e.total_distance_m + 100000;
    v_income := lvl.income_min_100km + floor(random() * (lvl.income_max_100km - lvl.income_min_100km + 1));
    v_paid := v_paid + (v_income - lvl.wage_per_100km);
    v_trips := v_trips + 1;
  end loop;
  if v_trips > 0 and v_paid <> 0 then
    perform private.add_money(v_me, v_paid, 'employee_delivery', null,
      'Livraison automatique du salarié (' || lvl.label || ', +' || (v_trips * 100) || ' km)');
  end if;
  update public.garage_employees set distance_m = e.distance_m, total_distance_m = e.total_distance_m,
    total_earned = total_earned + v_paid, last_tick_at = now() where user_id = v_me;
  return jsonb_build_object('active', true, 'level', e.level, 'distance_m', round(e.distance_m),
    'total_distance_m', round(e.total_distance_m), 'trips', v_trips, 'paid', v_paid);
end $$;

-- get_me() : ajoute le niveau du salarié (le reste du champ 'employee' est inchangé depuis 0021).
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
    'employee', private.employee_view(v_me)
  ) into v_out;
  return v_out;
end $$;

revoke all on function public.upgrade_employee() from public, anon, authenticated;
grant execute on function public.upgrade_employee() to authenticated;
