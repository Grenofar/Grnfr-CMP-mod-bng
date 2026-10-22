-- =====================================================================================
-- GRNFR Online - 0023 : classes de performance et de confort par véhicule (grand chantier Phase C, 22/10/2026).
-- Chaque véhicule du catalogue reçoit une classe perf et une classe confort (1 à 5, façon étoiles), copiées sur
-- le véhicule au moment de l'achat (garage_vehicles) pour que la classe reste fixée même si le catalogue change
-- plus tard. Valeurs choisies à la main selon le vrai comportement de chaque véhicule BeamNG (petites voitures
-- économiques = confort moyen/perf faible, supercars = perf max/confort faible, bus = perf faible/confort élevé
-- pour les passagers, versions "drag"/"race"/"track" = perf max/confort minimal, etc.) — approximation
-- raisonnable, pas une mesure physique exacte.
-- Le confort sert pour le taxi : plus la classe est haute, plus le pourboire est élevé ; en-dessous d'un certain
-- score de "douceur de conduite" (mesuré par le Lua pendant la course, approximatif comme le reste des
-- vérifications anti-triche du projet), le passager refuse carrément de payer. AUCUN de ces montants ne vient du
-- client : le serveur calcule tout à partir de private.cfg() et de dealership_catalog.
-- À exécuter APRÈS 0001-0022.
-- =====================================================================================

alter table public.dealership_catalog add column if not exists perf_class int not null default 3 check (perf_class between 1 and 5);
alter table public.dealership_catalog add column if not exists comfort_class int not null default 3 check (comfort_class between 1 and 5);
alter table public.garage_vehicles add column if not exists perf_class int not null default 3 check (perf_class between 1 and 5);
alter table public.garage_vehicles add column if not exists comfort_class int not null default 3 check (comfort_class between 1 and 5);

insert into public.server_config (key, value, description) values
  ('taxi_comfort_tip_per_class',  '5',  'Taxi : pourboire max par point de classe confort (multiplié par la douceur de conduite 0-1)'),
  ('taxi_comfort_refuse_below',   '30', 'Taxi : en-dessous de ce score de douceur de conduite (0-100), le passager refuse de payer')
on conflict (key) do nothing;

-- (model_key, config_key, perf, comfort) — config_key NULL = configuration par défaut du modèle.
with classes (model_key, config_key, perf, comfort) as (
  values
    ('barstow',   'i6a',                              2, 3),
    ('barstow',   null,                                3, 3),
    ('barstow',   '423a',                              4, 3),
    ('barstow',   'drag',                              5, 1),
    ('bastion',   null,                                3, 4),
    ('bastion',   'base_v6_awd_A',                     4, 4),
    ('bastion',   'police_v8_awd_A',                   4, 3),
    ('bastion',   'drag',                              5, 1),
    ('bolide',    null,                                5, 2),
    ('bolide',    'polizia',                           5, 2),
    ('bolide',    '320gtt_us',                         5, 1),
    ('bolide',    'race',                              5, 1),
    ('citybus',   'base',                               1, 4),
    ('citybus',   null,                                1, 4),
    ('citybus',   'highway',                           1, 5),
    ('citybus',   'rambus',                            2, 2),
    ('covet',     'covet_tutorial',                    1, 2),
    ('covet',     null,                                2, 3),
    ('covet',     '15zxi_M',                           3, 3),
    ('covet',     'turbo_rally',                       5, 1),
    ('etk800',    '844_150_M',                         2, 4),
    ('etk800',    null,                                3, 4),
    ('etk800',    '856xc_300_A',                       4, 5),
    ('etk800',    '846_ttSport_custom_DCT',            5, 3),
    ('fullsize',  'fleet',                             2, 3),
    ('fullsize',  null,                                2, 4),
    ('fullsize',  'drift',                             4, 2),
    ('fullsize',  'track',                             5, 1),
    ('miramar',   null,                                2, 3),
    ('miramar',   'base_facelift_M',                   2, 3),
    ('miramar',   'luxe_coupe_export_early_A',         3, 4),
    ('miramar',   'miramighty',                        3, 1),
    ('moonhawk',  'i6m',                               2, 3),
    ('moonhawk',  null,                                4, 3),
    ('moonhawk',  'detective',                         3, 3),
    ('moonhawk',  'drag',                              5, 1),
    ('pessima',   'DX_A',                              2, 4),
    ('pessima',   null,                                2, 4),
    ('pessima',   'GTz',                               4, 3),
    ('pessima',   'hillclimb',                         5, 1),
    ('pickup',    'd15_fleet_M_facelift',              1, 2),
    ('pickup',    null,                                2, 3),
    ('pickup',    'd25_ext_longbed_4wd_A_facelift',    2, 3),
    ('pickup',    'deserttruck_prerunner_A',           5, 1),
    ('scintilla', 'gt',                                5, 2),
    ('scintilla', null,                                5, 2),
    ('scintilla', 'custom',                            5, 1),
    ('scintilla', 'race',                              5, 1),
    ('sunburst2', 'base_EU_M',                         2, 3),
    ('sunburst2', 'sport_S_wagon_DCT',                 3, 3),
    ('sunburst2', null,                                3, 4),
    ('sunburst2', 'track_attack',                      5, 1),
    ('vivace',    'vivace_110_M',                      1, 3),
    ('vivace',    'vivace_S_270_DCT',                  4, 2),
    ('vivace',    null,                                2, 4),
    ('vivace',    'ardente_rally',                     5, 1)
)
update public.dealership_catalog c set perf_class = classes.perf, comfort_class = classes.comfort
from classes
where c.model_key = classes.model_key and coalesce(c.config_key, '') = coalesce(classes.config_key, '');

-- garage_vehicles déjà existants : copie la classe du catalogue correspondant (sinon reste au défaut 3/3).
update public.garage_vehicles g set perf_class = c.perf_class, comfort_class = c.comfort_class
from public.dealership_catalog c
where g.model_key = c.model_key and coalesce(g.config_key, '') = coalesce(c.config_key, '');

-- ------------------------------------------------------------------ catalogue : expose les classes à l'UI
create or replace function public.get_catalog() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'model_key', model_key, 'config_key', config_key,
         'name', name, 'price', price, 'perf_class', perf_class, 'comfort_class', comfort_class) order by price), '[]'::jsonb)
    from public.dealership_catalog where enabled $$;

-- ------------------------------------------------------------------ achat : copie la classe sur le véhicule
create or replace function public.buy_vehicle(p_catalog_id uuid, p_slot int default null, p_color text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  c public.dealership_catalog;
  v_slots int; v_slot int; v_id uuid;
begin
  select * into c from public.dealership_catalog where id = p_catalog_id and enabled;
  if not found then raise exception 'not_found'; end if;
  select garage_slots into v_slots from public.profiles where id = v_me for update;
  v_slot := coalesce(p_slot, private.first_free_slot(v_me));
  if v_slot is null then raise exception 'garage_full'; end if;
  if v_slot < 0 or v_slot >= v_slots then raise exception 'bad_slot'; end if;
  if exists (select 1 from public.garage_vehicles where owner_id = v_me and slot = v_slot) then raise exception 'slot_taken'; end if;
  perform private.add_money(v_me, -c.price, 'dealer_purchase', null, c.name);
  insert into public.garage_vehicles (owner_id, slot, model_key, config_key, color, value, perf_class, comfort_class)
  values (v_me, v_slot, c.model_key, c.config_key, left(p_color, 40), c.price, c.perf_class, c.comfort_class) returning id into v_id;
  return jsonb_build_object('vehicle_id', v_id, 'slot', v_slot);
end $$;

create or replace function public.buy_vehicle_insured(p_catalog_id uuid, p_insurance text default 'none', p_color text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  c public.dealership_catalog;
  v_slots int; v_slot int; v_id uuid; v_price bigint; v_prem bigint;
begin
  if private.insurance_plan(coalesce(p_insurance, 'none')) is null then raise exception 'bad_insurance'; end if;
  select * into c from public.dealership_catalog where id = p_catalog_id and enabled;
  if not found then raise exception 'not_found'; end if;
  select garage_slots into v_slots from public.profiles where id = v_me for update;
  v_slot := private.first_free_slot(v_me);
  if v_slot is null or v_slot >= v_slots then raise exception 'garage_full'; end if;
  select accepted_price into v_price from public.dealer_negotiations
   where user_id = v_me and catalog_id = c.id and status = 'accepted' and expires_at > now() and list_price = c.price;
  v_price := coalesce(v_price, c.price);
  v_prem := private.insurance_premium(coalesce(p_insurance, 'none'), c.price);
  perform private.add_money(v_me, -v_price, 'dealer_purchase', null, c.name,
    jsonb_build_object('list_price', c.price, 'negotiated', v_price < c.price));
  if v_prem > 0 then perform private.add_money(v_me, -v_prem, 'insurance', null, 'Assurance ' || p_insurance || ' : ' || c.name); end if;
  insert into public.garage_vehicles (owner_id, slot, model_key, config_key, color, value, insurance, perf_class, comfort_class)
  values (v_me, v_slot, c.model_key, c.config_key, left(p_color, 40), c.price, coalesce(p_insurance, 'none'), c.perf_class, c.comfort_class) returning id into v_id;
  delete from public.dealer_negotiations where user_id = v_me and catalog_id = c.id;
  return jsonb_build_object('vehicle_id', v_id, 'slot', v_slot, 'price', v_price, 'premium', v_prem);
end $$;

-- ------------------------------------------------------------------ pourboire/refus lié au confort (taxi)
-- p_model_key/p_config_key = véhicule du CHAUFFEUR au moment de l'arrivée ; p_smoothness (0-100, mesuré par le
-- Lua pendant la course, approximatif) = douceur de conduite, 100 = parfaitement doux. Jamais de montant calculé
-- côté client : seule la classe confort (dealership_catalog) et la config serveur décident du pourboire.
create or replace function private.comfort_tip(p_model_key text, p_config_key text, p_smoothness int) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_class int; v_smooth int := greatest(0, least(100, coalesce(p_smoothness, 70)));
begin
  select comfort_class into v_class from public.dealership_catalog
   where model_key = p_model_key and coalesce(config_key, '') = coalesce(p_config_key, '') limit 1;
  if v_class is null then v_class := 3; end if;
  return jsonb_build_object('comfort_class', v_class, 'smoothness', v_smooth,
    'refuse', v_smooth < private.cfg('taxi_comfort_refuse_below'),
    'tip', round(v_class * (v_smooth / 100.0) * private.cfg('taxi_comfort_tip_per_class')));
end $$;

create or replace function public.taxi_complete(p_id uuid, p_pos jsonb, p_model_key text default null,
                                                  p_config_key text default null, p_smoothness int default null) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); r public.taxi_requests; v_pay bigint; v_ct jsonb;
begin
  if not private.valid_pos(p_pos) then raise exception 'bad_position'; end if;
  select * into r from public.taxi_requests where id = p_id and driver_id = v_me for update;
  if not found or r.status <> 'picked_up' then raise exception 'request_unavailable'; end if;
  if private.dist(p_pos, r.dropoff) > 150 then raise exception 'too_far'; end if;
  if extract(epoch from (now() - r.picked_up_at)) < r.route_m / private.cfg('max_speed_mps') then raise exception 'too_fast'; end if;
  perform private.lock_two(v_me, r.passenger_id);
  update public.taxi_requests set status = 'completed', completed_at = now() where id = p_id;
  v_ct := private.comfort_tip(p_model_key, p_config_key, p_smoothness);
  if (v_ct->>'refuse')::boolean then
    perform private.add_money(r.passenger_id, r.fare, 'taxi_refund', v_me, 'Course trop secouée : remboursé');
    return 0;
  end if;
  v_pay := r.fare - floor(r.fare * private.cfg('taxi_fee_percent') / 100.0) + (v_ct->>'tip')::bigint;
  return private.add_money(v_me, v_pay, 'taxi_fare', r.passenger_id, 'Course de taxi'
    || case when (v_ct->>'tip')::bigint > 0 then ' (+' || (v_ct->>'tip') || ' pourboire confort)' else '' end);
end $$;

create or replace function public.complete_job(p_job uuid, p_pos jsonb, p_model_key text default null,
                                                 p_config_key text default null, p_smoothness int default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); j public.jobs; v_res jsonb; v_ct jsonb; v_tip bigint := 0;
begin
  if not private.valid_pos(p_pos) then raise exception 'bad_position'; end if;
  select * into j from public.jobs where id = p_job and user_id = v_me for update;
  if not found or j.status <> 'boarded' then raise exception 'job_unavailable'; end if;
  if private.dist(p_pos, j.dropoff) > 150 then raise exception 'too_far'; end if;
  if extract(epoch from (now() - j.boarded_at)) < j.min_seconds then raise exception 'too_fast'; end if;
  update public.jobs set status = 'completed', finished_at = now() where id = j.id;
  if j.kind = 'bot_taxi' then
    v_res := jsonb_build_object('paid', 0, 'charged', j.fare, 'capped', false);
  else -- npc_taxi / bus_leg : le joueur conduit, le confort affecte le pourboire (pas de refus, passager virtuel)
    v_ct := private.comfort_tip(p_model_key, p_config_key, p_smoothness);
    v_tip := (v_ct->>'tip')::bigint;
    if j.kind = 'npc_taxi' then
      v_res := private.capped_income(v_me, j.fare + v_tip, 'npc_taxi', 'Course (passager)');
    else
      v_res := private.capped_income(v_me, j.fare + v_tip, 'bus', 'Bus : ' || j.passengers || ' passager(s)');
    end if;
    v_res := v_res || jsonb_build_object('tip', v_tip);
  end if;
  return v_res;
end $$;

-- ------------------------------------------------------------------ get_me() : ajoute les classes des véhicules
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
    'delivery', (select jsonb_build_object('id', d.id, 'pickup', d.pickup, 'dropoff', d.dropoff, 'client_name', d.client_name,
                   'route_m', d.route_m, 'cargo_units', d.cargo_units, 'fare', d.fare, 'vehicle_id', d.vehicle_id)
                 from public.deliveries d where d.accepted_by = v_me and d.status = 'accepted' limit 1),
    'employee', private.employee_view(v_me)
  ) into v_out;
  return v_out;
end $$;

-- ------------------------------------------------------------------ catalogue public : expose les classes aussi
grant select on public.dealership_catalog to anon, authenticated; -- déjà le cas normalement, confirmé par sécurité
