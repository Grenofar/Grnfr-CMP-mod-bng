-- =====================================================================================
-- GRNFR Online - backend Supabase (économie, garage, marché, échanges, taxi, bus)
--
-- PRINCIPE DE SÉCURITÉ
--   * Les clients (le mod, le site) n'ont AUCUN droit d'écriture direct sur les tables.
--   * Toute écriture passe par des fonctions RPC "security definer" qui vérifient les règles :
--     l'argent est toujours créé / déplacé côté serveur, jamais décidé par le joueur.
--   * Chaque mouvement d'argent est inscrit dans le journal `transactions` (append-only).
--
-- INSTALLATION : coller ce fichier dans Supabase > SQL Editor > Run (ou `supabase db push`).
-- =====================================================================================

create schema if not exists private;
revoke all on schema private from public;

-- ------------------------------------------------------------------ configuration serveur
create table if not exists public.server_config (
  key         text primary key,
  value       jsonb not null,
  description text
);

insert into public.server_config (key, value, description) values
  ('starting_money',            '25000',  'Argent donné à l''inscription'),
  ('garage_slots',              '4',      'Places de garage par joueur (défaut)'),
  ('market_fee_percent',        '5',      'Commission prélevée sur les ventes privées (%)'),
  ('dealer_buyback_percent',    '50',     'Rachat d''un véhicule par le concessionnaire (% de sa valeur)'),
  ('max_transfer',              '1000000','Plafond d''un envoi d''argent entre joueurs'),
  ('max_listing_price',         '5000000','Prix maximum d''une annonce'),
  ('taxi_base_fare',            '8',      'Taxi : prise en charge'),
  ('taxi_per_km',               '3',      'Taxi : prix au km'),
  ('taxi_fee_percent',          '0',      'Taxi : commission du serveur sur les courses entre joueurs (%)'),
  ('taxi_request_ttl_seconds',  '180',    'Durée de vie d''une demande de taxi sans chauffeur'),
  ('bot_taxi_multiplier',       '1.5',    'Taxi IA : multiplicateur de prix'),
  ('bus_base_per_passenger',    '3',      'Bus : prix de base par passager'),
  ('bus_per_passenger_per_km',  '2',      'Bus : prix au km par passager'),
  ('npc_income_cap_per_hour',   '6000',   'Plafond de gains/heure venant du serveur (taxi PNJ, bus) : limite la triche'),
  ('max_speed_mps',             '60',     'Vitesse max crédible (m/s) pour valider la durée d''une course')
on conflict (key) do nothing;

create or replace function private.cfg(k text) returns numeric
language sql stable security definer set search_path = public, pg_temp as
$$ select (value #>> '{}')::numeric from public.server_config where key = k $$;

-- ------------------------------------------------------------------ profils
create table if not exists public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  username        text not null,
  balance         bigint not null default 0 check (balance >= 0),
  lifetime_earned bigint not null default 0,
  is_admin        boolean not null default false,
  garage_slots    int not null default 4 check (garage_slots between 1 and 50),
  duty            text check (duty in ('taxi', 'bus')),   -- chauffeur en service ?
  level           text,                                   -- carte où le joueur se trouve
  pos             jsonb,                                  -- dernière position connue {x,y,z}
  last_seen       timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  constraint username_format check (username ~ '^[A-Za-z0-9_]{3,20}$')
);
create unique index if not exists profiles_username_lower on public.profiles (lower(username));
create index if not exists profiles_wealth on public.profiles (balance desc);

-- ------------------------------------------------------------------ journal d'argent
create table if not exists public.transactions (
  id            bigserial primary key,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  kind          text not null,
  amount        bigint not null,            -- positif = gain, négatif = dépense
  balance_after bigint not null,
  counterparty  uuid references public.profiles (id) on delete set null,
  ref           text,
  meta          jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index if not exists transactions_user on public.transactions (user_id, created_at desc);

-- ------------------------------------------------------------------ concessionnaire & garage
create table if not exists public.dealership_catalog (
  id        uuid primary key default gen_random_uuid(),
  model_key text not null,
  config_key text,                 -- null = configuration par défaut du modèle
  name      text not null,
  price     bigint not null check (price > 0),
  enabled   boolean not null default true
);

create table if not exists public.garage_vehicles (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  slot       int not null check (slot >= 0),
  model_key  text not null,
  config_key text,
  color      text,
  nickname   text,
  value      bigint not null default 0 check (value >= 0),
  created_at timestamptz not null default now(),
  unique (owner_id, slot) deferrable initially immediate
);
create index if not exists garage_owner on public.garage_vehicles (owner_id);

-- ------------------------------------------------------------------ annonces (vente privée)
create table if not exists public.listings (
  id          uuid primary key default gen_random_uuid(),
  seller_id   uuid not null references public.profiles (id) on delete cascade,
  vehicle_id  uuid not null references public.garage_vehicles (id) on delete cascade,
  price       bigint not null check (price > 0),
  description text,
  status      text not null default 'open' check (status in ('open', 'sold', 'cancelled')),
  buyer_id    uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  sold_at     timestamptz
);
create unique index if not exists listings_one_open_per_vehicle on public.listings (vehicle_id) where status = 'open';
create index if not exists listings_open on public.listings (status, created_at desc);

-- ------------------------------------------------------------------ échanges directs entre joueurs
create table if not exists public.trades (
  id                 uuid primary key default gen_random_uuid(),
  proposer_id        uuid not null references public.profiles (id) on delete cascade,
  target_id          uuid not null references public.profiles (id) on delete cascade,
  offered_vehicle_id uuid references public.garage_vehicles (id) on delete cascade,   -- donné par le proposeur
  wanted_vehicle_id  uuid references public.garage_vehicles (id) on delete cascade,   -- demandé à la cible
  cash_from_proposer bigint not null default 0,   -- >0 : le proposeur paie ; <0 : la cible paie
  status             text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at         timestamptz not null default now(),
  resolved_at        timestamptz,
  check (offered_vehicle_id is not null or wanted_vehicle_id is not null),
  check (proposer_id <> target_id)
);
create index if not exists trades_target on public.trades (target_id, status);
create index if not exists trades_proposer on public.trades (proposer_id, status);

-- ------------------------------------------------------------------ taxi entre joueurs
create table if not exists public.taxi_requests (
  id           uuid primary key default gen_random_uuid(),
  passenger_id uuid not null references public.profiles (id) on delete cascade,
  driver_id    uuid references public.profiles (id) on delete set null,
  level        text,
  pickup       jsonb not null,
  dropoff      jsonb not null,
  route_m      int not null,
  fare         bigint not null check (fare >= 0),
  status       text not null default 'requested'
               check (status in ('requested', 'accepted', 'picked_up', 'completed', 'cancelled', 'expired')),
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  accepted_at  timestamptz,
  picked_up_at timestamptz,
  completed_at timestamptz
);
create index if not exists taxi_open on public.taxi_requests (status, level, created_at desc);

-- ------------------------------------------------------------------ jobs (taxi PNJ, bus, taxi IA)
create table if not exists public.jobs (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  kind        text not null check (kind in ('npc_taxi', 'bus_leg', 'bot_taxi')),
  level       text,
  pickup      jsonb not null,
  dropoff     jsonb not null,
  route_m     int not null,
  passengers  int not null default 1,
  fare        bigint not null check (fare >= 0),      -- npc_taxi / bus_leg : gain ; bot_taxi : prix payé
  min_seconds int not null,
  status      text not null default 'started' check (status in ('started', 'boarded', 'completed', 'cancelled', 'expired')),
  started_at  timestamptz not null default now(),
  boarded_at  timestamptz,
  finished_at timestamptz,
  expires_at  timestamptz not null
);
create index if not exists jobs_user on public.jobs (user_id, status);

-- =====================================================================================
-- Profil créé automatiquement à l'inscription
-- =====================================================================================
create or replace function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_name  text;
  v_short text := substr(replace(new.id::text, '-', ''), 1, 8);
  v_start bigint := private.cfg('starting_money')::bigint;
begin
  v_name := trim(coalesce(new.raw_user_meta_data ->> 'username', ''));
  if v_name !~ '^[A-Za-z0-9_]{3,20}$' then v_name := 'player_' || v_short; end if;
  if exists (select 1 from public.profiles where lower(username) = lower(v_name)) then
    v_name := substr(v_name, 1, 11) || '_' || v_short;
  end if;
  insert into public.profiles (id, username, balance, garage_slots)
  values (new.id, v_name, v_start, private.cfg('garage_slots')::int);
  insert into public.transactions (user_id, kind, amount, balance_after, ref)
  values (new.id, 'signup', v_start, v_start, 'Argent de départ');
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

-- =====================================================================================
-- Fonctions internes (non exposées : schéma private)
-- =====================================================================================

-- Ajoute (ou retire, si négatif) de l'argent et écrit le journal. Refuse un solde négatif.
create or replace function private.add_money(
  p_user uuid, p_amount bigint, p_kind text,
  p_counter uuid default null, p_ref text default null, p_meta jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare v_bal bigint;
begin
  begin
    update public.profiles
       set balance = balance + p_amount,
           lifetime_earned = lifetime_earned + case when p_amount > 0 and p_kind in
             ('taxi_fare', 'npc_taxi', 'bus', 'market_sale', 'trade_cash', 'dealer_sale') then p_amount else 0 end
     where id = p_user
    returning balance into v_bal;
  exception when check_violation then
    raise exception 'insufficient_funds';
  end;
  if v_bal is null then raise exception 'unknown_user'; end if;
  if p_amount <> 0 then
    insert into public.transactions (user_id, kind, amount, balance_after, counterparty, ref, meta)
    values (p_user, p_kind, p_amount, v_bal, p_counter, p_ref, p_meta);
  end if;
  return v_bal;
end $$;

-- Verrouille deux profils toujours dans le même ordre (évite les interblocages).
create or replace function private.lock_two(a uuid, b uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform 1 from public.profiles where id in (a, b) order by id for update;
end $$;

create or replace function private.dist(a jsonb, b jsonb) returns double precision
language sql immutable as $$
  select sqrt(power(coalesce((a ->> 'x')::float8, 0) - coalesce((b ->> 'x')::float8, 0), 2)
            + power(coalesce((a ->> 'y')::float8, 0) - coalesce((b ->> 'y')::float8, 0), 2)) $$;

create or replace function private.valid_pos(p jsonb) returns boolean
language sql immutable as $$
  select p is not null and jsonb_typeof(p) = 'object'
     and jsonb_typeof(p -> 'x') = 'number' and jsonb_typeof(p -> 'y') = 'number' $$;

-- Garde uniquement les champs attendus d'une position (évite de stocker n'importe quoi).
create or replace function private.clean_pos(p jsonb) returns jsonb
language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'x', (p ->> 'x')::float8, 'y', (p ->> 'y')::float8, 'z', (p ->> 'z')::float8,
    'name', left(p ->> 'name', 60))) $$;

create or replace function private.require_user() returns uuid
language plpgsql stable as $$
declare v uuid := auth.uid();
begin
  if v is null then raise exception 'not_authenticated'; end if;
  return v;
end $$;

create or replace function private.first_free_slot(p_owner uuid) returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select s from generate_series(0, (select garage_slots - 1 from public.profiles where id = p_owner)) s
   where not exists (select 1 from public.garage_vehicles g where g.owner_id = p_owner and g.slot = s)
   order by s limit 1 $$;

-- Remboursements + fermeture des demandes / jobs périmés. Appelée au début des RPC de taxi / jobs.
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
end $$;

-- Gains versés par le serveur (taxi PNJ, bus) : plafonnés par heure pour limiter la triche.
create or replace function private.capped_income(p_user uuid, p_amount bigint, p_kind text, p_ref text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_cap  bigint := private.cfg('npc_income_cap_per_hour')::bigint;
  v_used bigint;
  v_pay  bigint;
begin
  select coalesce(sum(amount), 0) into v_used from public.transactions
   where user_id = p_user and kind in ('npc_taxi', 'bus') and created_at > now() - interval '1 hour';
  v_pay := greatest(least(p_amount, v_cap - v_used), 0);
  if v_pay > 0 then perform private.add_money(p_user, v_pay, p_kind, null, p_ref); end if;
  return jsonb_build_object('paid', v_pay, 'asked', p_amount, 'capped', v_pay < p_amount);
end $$;

-- =====================================================================================
-- RPC publiques (appelées par le mod et le site)
-- =====================================================================================

-- Le pseudo est-il libre ? (appelable avant l'inscription)
create or replace function public.username_available(p_username text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select p_username ~ '^[A-Za-z0-9_]{3,20}$'
     and not exists (select 1 from public.profiles where lower(username) = lower(p_username)) $$;

-- Tout l'état du joueur en un seul appel (profil, garage, config, échanges en attente, annonces, course en cours).
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
                  'lifetime_earned', p.lifetime_earned)
                from public.profiles p where p.id = v_me),
    'vehicles', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'slot', g.slot, 'model_key', g.model_key,
                  'config_key', g.config_key, 'color', g.color, 'nickname', g.nickname, 'value', g.value,
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
         order by r.created_at desc limit 1) x)
  ) into v_out;
  return v_out;
end $$;

-- Battement de cœur : position, carte, service. Renvoie le solde (pour l'affichage).
create or replace function public.heartbeat(p_level text default null, p_pos jsonb default null, p_duty text default null)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_bal bigint;
begin
  if p_duty is not null and p_duty not in ('taxi', 'bus', 'none') then raise exception 'bad_duty'; end if;
  update public.profiles set
      last_seen = now(),
      level = coalesce(left(p_level, 60), level),
      pos = case when private.valid_pos(p_pos) then private.clean_pos(p_pos) else pos end,
      duty = case when p_duty is null then duty when p_duty = 'none' then null else p_duty end
   where id = v_me returning balance into v_bal;
  return v_bal;
end $$;

-- Joueurs connectés (vus il y a moins de 90 s)
create or replace function public.get_online_players() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('username', username, 'level', level, 'duty', duty) order by username), '[]'::jsonb)
    from public.profiles where last_seen > now() - interval '90 seconds' $$;

-- Classement des richesses : argent + valeur des véhicules. Public (le site l'affiche sans connexion).
create or replace function public.get_leaderboard(p_limit int default 25) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.wealth desc), '[]'::jsonb) from (
    select p.username, p.balance, coalesce(v.total, 0) as vehicles_value, p.balance + coalesce(v.total, 0) as wealth,
           coalesce(v.n, 0) as vehicles
      from public.profiles p
      left join (select owner_id, sum(value) as total, count(*) as n from public.garage_vehicles group by owner_id) v on v.owner_id = p.id
     order by wealth desc limit greatest(1, least(coalesce(p_limit, 25), 100))
  ) x $$;

-- ------------------------------------------------------------------ argent entre joueurs
create or replace function public.send_money(p_username text, p_amount bigint) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_to uuid; v_bal bigint;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'bad_amount'; end if;
  if p_amount > private.cfg('max_transfer') then raise exception 'over_limit'; end if;
  select id into v_to from public.profiles where lower(username) = lower(p_username);
  if v_to is null then raise exception 'unknown_user'; end if;
  if v_to = v_me then raise exception 'self_transfer'; end if;
  perform private.lock_two(v_me, v_to);
  v_bal := private.add_money(v_me, -p_amount, 'transfer_out', v_to, 'Envoi à ' || p_username);
  perform private.add_money(v_to, p_amount, 'transfer_in', v_me, 'Reçu de ' || (select username from public.profiles where id = v_me));
  return v_bal;
end $$;

-- ------------------------------------------------------------------ administration
create or replace function private.require_admin() returns uuid
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v uuid := private.require_user();
begin
  if not exists (select 1 from public.profiles where id = v and is_admin) then raise exception 'forbidden'; end if;
  return v;
end $$;

-- Donne (ou retire, si négatif) de l'argent à un joueur. Réservé aux admins. Le solde ne peut pas devenir négatif.
create or replace function public.admin_give_money(p_username text, p_amount bigint, p_reason text default null) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_admin uuid := private.require_admin(); v_to uuid; v_cur bigint; v_amt bigint;
begin
  if p_amount is null or p_amount = 0 then raise exception 'bad_amount'; end if;
  select id, balance into v_to, v_cur from public.profiles where lower(username) = lower(p_username) for update;
  if v_to is null then raise exception 'unknown_user'; end if;
  v_amt := case when p_amount < 0 then -least(-p_amount, v_cur) else p_amount end;
  return private.add_money(v_to, v_amt, 'admin', v_admin, coalesce(left(p_reason, 120), 'Ajustement admin'));
end $$;

create or replace function public.admin_set_config(p_key text, p_value jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform private.require_admin();
  if not exists (select 1 from public.server_config where key = p_key) then raise exception 'unknown_key'; end if;
  if jsonb_typeof(p_value) <> 'number' then raise exception 'bad_value'; end if;
  update public.server_config set value = p_value where key = p_key;
end $$;

create or replace function public.admin_set_garage_slots(p_username text, p_slots int) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform private.require_admin();
  if p_slots < 1 or p_slots > 50 then raise exception 'bad_value'; end if;
  if exists (select 1 from public.garage_vehicles g join public.profiles p on p.id = g.owner_id
              where lower(p.username) = lower(p_username) and g.slot >= p_slots) then raise exception 'slots_in_use'; end if;
  update public.profiles set garage_slots = p_slots where lower(username) = lower(p_username);
  if not found then raise exception 'unknown_user'; end if;
end $$;

create or replace function public.admin_upsert_catalog(p_id uuid, p_model text, p_config text, p_name text, p_price bigint, p_enabled boolean default true)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v uuid;
begin
  perform private.require_admin();
  if p_price is null or p_price <= 0 then raise exception 'bad_amount'; end if;
  if p_id is null then
    insert into public.dealership_catalog (model_key, config_key, name, price, enabled)
    values (p_model, nullif(p_config, ''), p_name, p_price, p_enabled) returning id into v;
  else
    update public.dealership_catalog set model_key = p_model, config_key = nullif(p_config, ''), name = p_name,
           price = p_price, enabled = p_enabled where id = p_id returning id into v;
    if v is null then raise exception 'not_found'; end if;
  end if;
  return v;
end $$;

-- ------------------------------------------------------------------ concessionnaire & garage
create or replace function public.get_catalog() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'model_key', model_key, 'config_key', config_key,
         'name', name, 'price', price) order by price), '[]'::jsonb)
    from public.dealership_catalog where enabled $$;

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
  insert into public.garage_vehicles (owner_id, slot, model_key, config_key, color, value)
  values (v_me, v_slot, c.model_key, c.config_key, left(p_color, 40), c.price) returning id into v_id;
  return jsonb_build_object('vehicle_id', v_id, 'slot', v_slot);
end $$;

create or replace function public.sell_vehicle_to_dealer(p_vehicle_id uuid) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); g public.garage_vehicles; v_price bigint;
begin
  select * into g from public.garage_vehicles where id = p_vehicle_id and owner_id = v_me for update;
  if not found then raise exception 'not_found'; end if;
  if exists (select 1 from public.listings where vehicle_id = g.id and status = 'open') then raise exception 'vehicle_listed'; end if;
  if exists (select 1 from public.trades where status = 'pending' and (offered_vehicle_id = g.id or wanted_vehicle_id = g.id)) then
    raise exception 'vehicle_in_trade';
  end if;
  v_price := floor(g.value * private.cfg('dealer_buyback_percent') / 100.0);
  delete from public.garage_vehicles where id = g.id;
  return private.add_money(v_me, v_price, 'dealer_sale', null, coalesce(g.nickname, g.model_key));
end $$;

create or replace function public.update_vehicle_look(p_vehicle_id uuid, p_color text, p_nickname text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user();
begin
  update public.garage_vehicles set color = left(p_color, 40), nickname = left(p_nickname, 30)
   where id = p_vehicle_id and owner_id = v_me;
  if not found then raise exception 'not_found'; end if;
end $$;

-- ------------------------------------------------------------------ annonces
create or replace function public.create_listing(p_vehicle_id uuid, p_price bigint, p_description text default null) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_id uuid;
begin
  if p_price is null or p_price <= 0 then raise exception 'bad_amount'; end if;
  if p_price > private.cfg('max_listing_price') then raise exception 'over_limit'; end if;
  perform 1 from public.garage_vehicles where id = p_vehicle_id and owner_id = v_me for update;
  if not found then raise exception 'not_found'; end if;
  if exists (select 1 from public.listings where vehicle_id = p_vehicle_id and status = 'open') then raise exception 'already_listed'; end if;
  if exists (select 1 from public.trades where status = 'pending' and (offered_vehicle_id = p_vehicle_id or wanted_vehicle_id = p_vehicle_id)) then
    raise exception 'vehicle_in_trade';
  end if;
  insert into public.listings (seller_id, vehicle_id, price, description)
  values (v_me, p_vehicle_id, p_price, left(p_description, 200)) returning id into v_id;
  return v_id;
end $$;

create or replace function public.cancel_listing(p_listing_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user();
begin
  update public.listings set status = 'cancelled' where id = p_listing_id and seller_id = v_me and status = 'open';
  if not found then raise exception 'not_found'; end if;
end $$;

-- Annonces ouvertes, avec les infos du véhicule et du vendeur
create or replace function public.get_market(p_limit int default 50, p_offset int default 0) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'price', l.price, 'description', l.description,
           'seller', p.username, 'seller_id', l.seller_id, 'created_at', l.created_at,
           'model_key', g.model_key, 'config_key', g.config_key, 'color', g.color, 'nickname', g.nickname, 'value', g.value)
           order by l.created_at desc), '[]'::jsonb)
    from (select * from public.listings where status = 'open' order by created_at desc
           limit greatest(1, least(coalesce(p_limit, 50), 100)) offset greatest(coalesce(p_offset, 0), 0)) l
    join public.garage_vehicles g on g.id = l.vehicle_id
    join public.profiles p on p.id = l.seller_id $$;

create or replace function public.buy_listing(p_listing_id uuid, p_slot int default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  l public.listings; v_slots int; v_slot int; v_fee bigint; v_seller_name text;
begin
  select * into l from public.listings where id = p_listing_id for update;
  if not found or l.status <> 'open' then raise exception 'listing_unavailable'; end if;
  if l.seller_id = v_me then raise exception 'own_listing'; end if;
  perform private.lock_two(v_me, l.seller_id);
  select garage_slots into v_slots from public.profiles where id = v_me;
  v_slot := coalesce(p_slot, private.first_free_slot(v_me));
  if v_slot is null then raise exception 'garage_full'; end if;
  if v_slot < 0 or v_slot >= v_slots then raise exception 'bad_slot'; end if;
  if exists (select 1 from public.garage_vehicles where owner_id = v_me and slot = v_slot) then raise exception 'slot_taken'; end if;
  perform 1 from public.garage_vehicles where id = l.vehicle_id and owner_id = l.seller_id for update;
  if not found then raise exception 'listing_unavailable'; end if;
  v_fee := floor(l.price * private.cfg('market_fee_percent') / 100.0);
  select username into v_seller_name from public.profiles where id = l.seller_id;
  perform private.add_money(v_me, -l.price, 'market_purchase', l.seller_id, 'Achat à ' || v_seller_name);
  perform private.add_money(l.seller_id, l.price - v_fee, 'market_sale', v_me, 'Vente (commission ' || v_fee || ')');
  update public.garage_vehicles set owner_id = v_me, slot = v_slot, value = l.price where id = l.vehicle_id;
  update public.listings set status = 'sold', buyer_id = v_me, sold_at = now() where id = l.id;
  return jsonb_build_object('vehicle_id', l.vehicle_id, 'slot', v_slot, 'price', l.price);
end $$;

-- ------------------------------------------------------------------ échanges de véhicules
create or replace function public.propose_trade(p_username text, p_offered uuid, p_wanted uuid, p_cash bigint default 0) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_to uuid; v_id uuid;
begin
  select id into v_to from public.profiles where lower(username) = lower(p_username);
  if v_to is null then raise exception 'unknown_user'; end if;
  if v_to = v_me then raise exception 'self_trade'; end if;
  if p_offered is null and p_wanted is null then raise exception 'empty_trade'; end if;
  if abs(coalesce(p_cash, 0)) > private.cfg('max_transfer') then raise exception 'over_limit'; end if;
  if p_offered is not null and not exists (select 1 from public.garage_vehicles where id = p_offered and owner_id = v_me) then raise exception 'not_found'; end if;
  if p_wanted is not null and not exists (select 1 from public.garage_vehicles where id = p_wanted and owner_id = v_to) then raise exception 'not_found'; end if;
  if exists (select 1 from public.listings where status = 'open' and vehicle_id in (coalesce(p_offered, p_wanted), coalesce(p_wanted, p_offered))) then
    raise exception 'vehicle_listed';
  end if;
  insert into public.trades (proposer_id, target_id, offered_vehicle_id, wanted_vehicle_id, cash_from_proposer)
  values (v_me, v_to, p_offered, p_wanted, coalesce(p_cash, 0)) returning id into v_id;
  return v_id;
end $$;

create or replace function public.get_trades() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'direction', case when t.proposer_id = auth.uid() then 'out' else 'in' end,
      'proposer', pp.username, 'target', tp.username, 'cash_from_proposer', t.cash_from_proposer,
      'offered', case when o.id is null then null else jsonb_build_object('id', o.id, 'model_key', o.model_key, 'config_key', o.config_key, 'nickname', o.nickname, 'value', o.value) end,
      'wanted',  case when w.id is null then null else jsonb_build_object('id', w.id, 'model_key', w.model_key, 'config_key', w.config_key, 'nickname', w.nickname, 'value', w.value) end,
      'created_at', t.created_at) order by t.created_at desc), '[]'::jsonb)
    from public.trades t
    join public.profiles pp on pp.id = t.proposer_id
    join public.profiles tp on tp.id = t.target_id
    left join public.garage_vehicles o on o.id = t.offered_vehicle_id
    left join public.garage_vehicles w on w.id = t.wanted_vehicle_id
   where t.status = 'pending' and (t.proposer_id = auth.uid() or t.target_id = auth.uid()) $$;

create or replace function public.cancel_trade(p_trade_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user();
begin
  update public.trades set status = 'cancelled', resolved_at = now() where id = p_trade_id and proposer_id = v_me and status = 'pending';
  if not found then raise exception 'not_found'; end if;
end $$;

-- La cible accepte ou refuse. À l'acceptation : véhicules et argent échangés en une seule transaction.
create or replace function public.respond_trade(p_trade_id uuid, p_accept boolean, p_slot int default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  t public.trades; o public.garage_vehicles; w public.garage_vehicles;
  v_slot int; v_slots int; v_payer uuid; v_payee uuid; v_amt bigint;
begin
  select * into t from public.trades where id = p_trade_id for update;
  if not found or t.status <> 'pending' or t.target_id <> v_me then raise exception 'not_found'; end if;
  if not p_accept then
    update public.trades set status = 'declined', resolved_at = now() where id = t.id;
    return;
  end if;
  perform private.lock_two(t.proposer_id, t.target_id);
  if t.offered_vehicle_id is not null then
    select * into o from public.garage_vehicles where id = t.offered_vehicle_id and owner_id = t.proposer_id for update;
    if not found then raise exception 'trade_invalid'; end if;
    if exists (select 1 from public.listings where vehicle_id = o.id and status = 'open') then raise exception 'trade_invalid'; end if;
  end if;
  if t.wanted_vehicle_id is not null then
    select * into w from public.garage_vehicles where id = t.wanted_vehicle_id and owner_id = t.target_id for update;
    if not found then raise exception 'trade_invalid'; end if;
    if exists (select 1 from public.listings where vehicle_id = w.id and status = 'open') then raise exception 'trade_invalid'; end if;
  end if;
  -- argent
  if t.cash_from_proposer <> 0 then
    v_amt := abs(t.cash_from_proposer);
    v_payer := case when t.cash_from_proposer > 0 then t.proposer_id else t.target_id end;
    v_payee := case when t.cash_from_proposer > 0 then t.target_id else t.proposer_id end;
    perform private.add_money(v_payer, -v_amt, 'trade_cash', v_payee, 'Échange de véhicule');
    perform private.add_money(v_payee, v_amt, 'trade_cash', v_payer, 'Échange de véhicule');
  end if;
  -- véhicules
  if o.id is not null and w.id is not null then
    set constraints all deferred;
    update public.garage_vehicles set owner_id = t.target_id,   slot = w.slot where id = o.id;
    update public.garage_vehicles set owner_id = t.proposer_id, slot = o.slot where id = w.id;
    set constraints all immediate;
  elsif o.id is not null then            -- le proposeur donne : place libre chez la cible
    select garage_slots into v_slots from public.profiles where id = t.target_id;
    v_slot := coalesce(p_slot, private.first_free_slot(t.target_id));
    if v_slot is null or v_slot < 0 or v_slot >= v_slots then raise exception 'garage_full'; end if;
    if exists (select 1 from public.garage_vehicles where owner_id = t.target_id and slot = v_slot) then raise exception 'slot_taken'; end if;
    update public.garage_vehicles set owner_id = t.target_id, slot = v_slot where id = o.id;
  else                                    -- la cible donne : place libre chez le proposeur
    v_slot := private.first_free_slot(t.proposer_id);
    if v_slot is null then raise exception 'garage_full'; end if;
    update public.garage_vehicles set owner_id = t.proposer_id, slot = v_slot where id = w.id;
  end if;
  update public.trades set status = 'accepted', resolved_at = now() where id = t.id;
end $$;

-- =====================================================================================
-- TAXI entre joueurs : le passager paie d'avance (séquestre), le chauffeur est payé à l'arrivée.
-- =====================================================================================
create or replace function private.route_length(p_pickup jsonb, p_dropoff jsonb, p_claimed int) returns int
language plpgsql immutable as $$
declare v_straight float8 := private.dist(p_pickup, p_dropoff);
begin
  -- la distance annoncée par le jeu (trajet routier) est acceptée entre 1x et 2,5x la ligne droite
  return round(least(greatest(coalesce(p_claimed, v_straight), v_straight), v_straight * 2.5));
end $$;

create or replace function public.request_taxi(p_level text, p_pickup jsonb, p_dropoff jsonb, p_distance_m int default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user(); v_route int; v_fare bigint; v_id uuid;
begin
  perform private.expire_stale();
  if not (private.valid_pos(p_pickup) and private.valid_pos(p_dropoff)) then raise exception 'bad_position'; end if;
  if exists (select 1 from public.taxi_requests where passenger_id = v_me and status in ('requested', 'accepted', 'picked_up')) then
    raise exception 'already_active';
  end if;
  if private.dist(p_pickup, p_dropoff) < 150 then raise exception 'too_short'; end if;
  v_route := private.route_length(p_pickup, p_dropoff, p_distance_m);
  v_fare := round(private.cfg('taxi_base_fare') + private.cfg('taxi_per_km') * v_route / 1000.0);
  perform private.add_money(v_me, -v_fare, 'taxi_escrow', null, 'Course de taxi (réservée)');
  insert into public.taxi_requests (passenger_id, level, pickup, dropoff, route_m, fare, expires_at)
  values (v_me, left(p_level, 60), private.clean_pos(p_pickup), private.clean_pos(p_dropoff), v_route, v_fare,
          now() + make_interval(secs => private.cfg('taxi_request_ttl_seconds')::int))
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'fare', v_fare, 'route_m', v_route);
end $$;

create or replace function public.get_open_taxi_requests(p_level text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_out jsonb;
begin
  perform private.expire_stale();
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'passenger', p.username, 'pickup', r.pickup, 'dropoff', r.dropoff,
           'route_m', r.route_m, 'fare', r.fare, 'created_at', r.created_at) order by r.created_at), '[]'::jsonb)
    into v_out
    from public.taxi_requests r join public.profiles p on p.id = r.passenger_id
   where r.status = 'requested' and r.passenger_id <> v_me and (p_level is null or r.level = p_level);
  return v_out;
end $$;

create or replace function public.accept_taxi_request(p_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); r public.taxi_requests;
begin
  perform private.expire_stale();
  select * into r from public.taxi_requests where id = p_id for update;
  if not found or r.status <> 'requested' then raise exception 'request_unavailable'; end if;
  if r.passenger_id = v_me then raise exception 'own_request'; end if;
  if exists (select 1 from public.taxi_requests where driver_id = v_me and status in ('accepted', 'picked_up')) then raise exception 'driver_busy'; end if;
  update public.taxi_requests set status = 'accepted', driver_id = v_me, accepted_at = now() where id = p_id;
end $$;

create or replace function public.taxi_pickup(p_id uuid, p_pos jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); r public.taxi_requests;
begin
  if not private.valid_pos(p_pos) then raise exception 'bad_position'; end if;
  select * into r from public.taxi_requests where id = p_id and driver_id = v_me for update;
  if not found or r.status <> 'accepted' then raise exception 'request_unavailable'; end if;
  if private.dist(p_pos, r.pickup) > 150 then raise exception 'too_far'; end if;
  update public.taxi_requests set status = 'picked_up', picked_up_at = now() where id = p_id;
end $$;

create or replace function public.taxi_complete(p_id uuid, p_pos jsonb) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); r public.taxi_requests; v_pay bigint;
begin
  if not private.valid_pos(p_pos) then raise exception 'bad_position'; end if;
  select * into r from public.taxi_requests where id = p_id and driver_id = v_me for update;
  if not found or r.status <> 'picked_up' then raise exception 'request_unavailable'; end if;
  if private.dist(p_pos, r.dropoff) > 150 then raise exception 'too_far'; end if;
  if extract(epoch from (now() - r.picked_up_at)) < r.route_m / private.cfg('max_speed_mps') then raise exception 'too_fast'; end if;
  perform private.lock_two(v_me, r.passenger_id);
  v_pay := r.fare - floor(r.fare * private.cfg('taxi_fee_percent') / 100.0);
  update public.taxi_requests set status = 'completed', completed_at = now() where id = p_id;
  return private.add_money(v_me, v_pay, 'taxi_fare', r.passenger_id, 'Course de taxi');
end $$;

-- Passager : annule (remboursé tant que la course n'a pas commencé). Chauffeur : abandonne.
create or replace function public.cancel_taxi_request(p_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); r public.taxi_requests;
begin
  select * into r from public.taxi_requests where id = p_id for update;
  if not found or r.status not in ('requested', 'accepted', 'picked_up') then raise exception 'not_found'; end if;
  if r.passenger_id = v_me then
    if r.status = 'picked_up' then raise exception 'ride_started'; end if;
    update public.taxi_requests set status = 'cancelled' where id = p_id;
    perform private.add_money(r.passenger_id, r.fare, 'taxi_refund', null, 'Course annulée');
  elsif r.driver_id = v_me then
    if r.status = 'accepted' and r.expires_at > now() then      -- retourne dans la liste d'attente
      update public.taxi_requests set status = 'requested', driver_id = null, accepted_at = null where id = p_id;
    else                                                        -- en cours de route ou périmée : le passager est remboursé
      update public.taxi_requests set status = 'cancelled' where id = p_id;
      perform private.add_money(r.passenger_id, r.fare, 'taxi_refund', null, 'Chauffeur indisponible');
    end if;
  else
    raise exception 'not_found';
  end if;
end $$;

-- =====================================================================================
-- JOBS : taxi avec passagers PNJ, tronçons de bus, taxi IA (le joueur est passager)
--   start_job -> board_job (près du départ) -> complete_job (près de l'arrivée, durée crédible)
-- =====================================================================================
create or replace function public.start_job(p_kind text, p_level text, p_pickup jsonb, p_dropoff jsonb,
                                            p_distance_m int default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user(); v_route int; v_pax int := 1; v_km numeric; v_fare bigint; v_id uuid; v_min int;
  old record;
begin
  perform private.expire_stale();
  if p_kind not in ('npc_taxi', 'bus_leg', 'bot_taxi') then raise exception 'bad_kind'; end if;
  if not (private.valid_pos(p_pickup) and private.valid_pos(p_dropoff)) then raise exception 'bad_position'; end if;
  if private.dist(p_pickup, p_dropoff) < 150 then raise exception 'too_short'; end if;
  -- une seule mission active par type : l'ancienne est annulée (taxi IA non embarqué : remboursé)
  for old in select id, kind, fare, status from public.jobs where user_id = v_me and kind = p_kind and status in ('started', 'boarded') for update loop
    update public.jobs set status = 'cancelled', finished_at = now() where id = old.id;
    if old.kind = 'bot_taxi' and old.status = 'started' then perform private.add_money(v_me, old.fare, 'taxi_refund', null, 'Taxi IA annulé'); end if;
  end loop;
  v_route := private.route_length(p_pickup, p_dropoff, p_distance_m);
  v_km := v_route / 1000.0;
  if p_kind = 'npc_taxi' then
    v_fare := round(private.cfg('taxi_base_fare') + private.cfg('taxi_per_km') * v_km);
  elsif p_kind = 'bus_leg' then
    v_pax := 1 + floor(random() * 8)::int;
    v_fare := round(v_pax * (private.cfg('bus_base_per_passenger') + private.cfg('bus_per_passenger_per_km') * v_km));
  else
    v_fare := round((private.cfg('taxi_base_fare') + private.cfg('taxi_per_km') * v_km) * private.cfg('bot_taxi_multiplier'));
    perform private.add_money(v_me, -v_fare, 'taxi_escrow', null, 'Taxi IA (réservé)');
  end if;
  v_min := ceil(v_route / private.cfg('max_speed_mps'));
  insert into public.jobs (user_id, kind, level, pickup, dropoff, route_m, passengers, fare, min_seconds, expires_at)
  values (v_me, p_kind, left(p_level, 60), private.clean_pos(p_pickup), private.clean_pos(p_dropoff), v_route, v_pax, v_fare, v_min,
          now() + interval '2 hours')
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'fare', v_fare, 'route_m', v_route, 'passengers', v_pax, 'min_seconds', v_min);
end $$;

create or replace function public.board_job(p_job uuid, p_pos jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); j public.jobs;
begin
  if not private.valid_pos(p_pos) then raise exception 'bad_position'; end if;
  select * into j from public.jobs where id = p_job and user_id = v_me for update;
  if not found or j.status <> 'started' then raise exception 'job_unavailable'; end if;
  if private.dist(p_pos, j.pickup) > 150 then raise exception 'too_far'; end if;
  update public.jobs set status = 'boarded', boarded_at = now() where id = j.id;
end $$;

create or replace function public.complete_job(p_job uuid, p_pos jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); j public.jobs; v_res jsonb;
begin
  if not private.valid_pos(p_pos) then raise exception 'bad_position'; end if;
  select * into j from public.jobs where id = p_job and user_id = v_me for update;
  if not found or j.status <> 'boarded' then raise exception 'job_unavailable'; end if;
  if private.dist(p_pos, j.dropoff) > 150 then raise exception 'too_far'; end if;
  if extract(epoch from (now() - j.boarded_at)) < j.min_seconds then raise exception 'too_fast'; end if;
  update public.jobs set status = 'completed', finished_at = now() where id = j.id;
  if j.kind = 'bot_taxi' then
    v_res := jsonb_build_object('paid', 0, 'charged', j.fare, 'capped', false);
  elsif j.kind = 'npc_taxi' then
    v_res := private.capped_income(v_me, j.fare, 'npc_taxi', 'Course (passager)');
  else
    v_res := private.capped_income(v_me, j.fare, 'bus', 'Bus : ' || j.passengers || ' passager(s)');
  end if;
  return v_res;
end $$;

create or replace function public.cancel_job(p_job uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); j public.jobs;
begin
  select * into j from public.jobs where id = p_job and user_id = v_me for update;
  if not found or j.status not in ('started', 'boarded') then raise exception 'job_unavailable'; end if;
  update public.jobs set status = 'cancelled', finished_at = now() where id = j.id;
  if j.kind = 'bot_taxi' and j.status = 'started' then
    perform private.add_money(v_me, j.fare, 'taxi_refund', null, 'Taxi IA annulé');
  end if;
end $$;

create or replace function public.get_my_transactions(p_limit int default 30) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'amount', amount, 'balance_after', balance_after,
         'ref', ref, 'created_at', created_at) order by id desc), '[]'::jsonb)
    from (select * from public.transactions where user_id = auth.uid() order by id desc limit greatest(1, least(coalesce(p_limit, 30), 100))) t $$;

-- =====================================================================================
-- DROITS : aucun accès direct aux tables, uniquement lecture de sa propre ligne + RPC.
-- =====================================================================================
alter table public.server_config      enable row level security;
alter table public.profiles           enable row level security;
alter table public.transactions       enable row level security;
alter table public.dealership_catalog enable row level security;
alter table public.garage_vehicles    enable row level security;
alter table public.listings           enable row level security;
alter table public.trades             enable row level security;
alter table public.taxi_requests      enable row level security;
alter table public.jobs               enable row level security;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- lecture : sa propre ligne seulement (tout le reste passe par les fonctions get_*)
create policy cfg_read      on public.server_config for select to anon, authenticated using (true);
create policy profiles_self on public.profiles      for select to authenticated using (id = auth.uid());
create policy tx_self       on public.transactions  for select to authenticated using (user_id = auth.uid());
create policy garage_self   on public.garage_vehicles for select to authenticated using (owner_id = auth.uid());
create policy jobs_self     on public.jobs          for select to authenticated using (user_id = auth.uid());
grant select on public.server_config to anon, authenticated;
grant select on public.profiles, public.transactions, public.garage_vehicles, public.jobs to authenticated;

-- fonctions publiques
grant execute on function
  public.username_available(text),
  public.get_leaderboard(int),
  public.get_catalog()
  to anon, authenticated;
grant execute on function
  public.get_me(), public.heartbeat(text, jsonb, text), public.get_online_players(),
  public.send_money(text, bigint),
  public.admin_give_money(text, bigint, text), public.admin_set_config(text, jsonb),
  public.admin_set_garage_slots(text, int), public.admin_upsert_catalog(uuid, text, text, text, bigint, boolean),
  public.buy_vehicle(uuid, int, text), public.sell_vehicle_to_dealer(uuid), public.update_vehicle_look(uuid, text, text),
  public.create_listing(uuid, bigint, text), public.cancel_listing(uuid), public.get_market(int, int), public.buy_listing(uuid, int),
  public.propose_trade(text, uuid, uuid, bigint), public.get_trades(), public.cancel_trade(uuid), public.respond_trade(uuid, boolean, int),
  public.request_taxi(text, jsonb, jsonb, int), public.get_open_taxi_requests(text), public.accept_taxi_request(uuid),
  public.taxi_pickup(uuid, jsonb), public.taxi_complete(uuid, jsonb), public.cancel_taxi_request(uuid),
  public.start_job(text, text, jsonb, jsonb, int), public.board_job(uuid, jsonb), public.complete_job(uuid, jsonb), public.cancel_job(uuid),
  public.get_my_transactions(int)
  to authenticated;

-- =====================================================================================
-- Catalogue de départ (modifiable : voir admin_upsert_catalog). Les noms de modèles sont ceux du jeu de base ;
-- vérifiez-les avec votre version de BeamNG et adaptez les prix.
-- =====================================================================================
insert into public.dealership_catalog (model_key, config_key, name, price)
select * from (values
  ('covet',     null::text, 'Ibishu Covet',          6500::bigint),
  ('pessima',   null,       'Ibishu Pessima',        9000),
  ('sunburst2', null,       'Hirochi Sunburst',     14000),
  ('vivace',    null,       'Cherrier Vivace',      16000),
  ('miramar',   null,       'Ibishu Miramar',       18000),
  ('pickup',    null,       'Gavril D-Series',      21000),
  ('etk800',    null,       'ETK 800 Series',       32000),
  ('bastion',   null,       'Bruckell Bastion',     45000),
  ('barstow',   null,       'Gavril Barstow',       38000),
  ('moonhawk',  null,       'Bruckell Moonhawk',    30000),
  ('bolide',    null,       'Civetta Bolide',       80000),
  ('scintilla', null,       'Civetta Scintilla',   250000),
  ('fullsize',  null,       'Gavril Grand Marshal', 24000),
  ('citybus',   null,       'Wentward DT40L (bus)', 60000)
) as v(model_key, config_key, name, price)
where not exists (select 1 from public.dealership_catalog);
