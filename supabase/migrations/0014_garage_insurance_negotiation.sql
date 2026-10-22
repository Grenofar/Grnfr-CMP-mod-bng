-- =====================================================================================
-- GRNFR Online - 0014 : vrais garages, assurances, négociation avec le concessionnaire.
-- À exécuter APRÈS 0001-0013.
--
-- * release_garage_spot() : depuis le mod 2.4.0, un garage n'est attribué QUE dans un vrai garage de la carte
--   (garages de la carrière du jeu, avec leur ordinateur = la tablette). Les garages attribués avant, au hasard sur
--   une route, sont rendus par le mod lui-même (aucun vrai garage à cet endroit), puis il en redemande un.
-- * Assurances : un niveau par véhicule (none / basic / comfort / premium). La prime (pourcentage de la valeur) est
--   payée à l'achat ou au changement vers un niveau supérieur ; la franchise servira aux réparations (phase suivante).
-- * Négociation : le joueur fait des offres, le concessionnaire (un « bot » côté serveur, impossible à tricher depuis
--   le client) accepte, contre-propose ou se vexe. Prix plancher secret tiré au hasard à chaque négociation
--   (80 à 90 % du prix affiché), patience limitée (3 à 5 offres), offre insultante (< 60 %) = négociation rompue.
--   buy_vehicle_insured() achète au prix négocié s'il y en a un d'accepté, sinon au prix affiché.
-- =====================================================================================

-- ------------------------------------------------------------------ rendre son garage
create or replace function public.release_garage_spot() returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_srv uuid;
begin
  select server_id into v_srv from public.server_members where user_id = v_me;
  if v_srv is null then raise exception 'not_in_server'; end if;
  delete from public.garage_spots where server_id = v_srv and user_id = v_me;
end $$;

-- ------------------------------------------------------------------ assurances
alter table public.garage_vehicles add column if not exists insurance text not null default 'none';
do $$ begin
  alter table public.garage_vehicles add constraint garage_vehicles_insurance check (insurance in ('none', 'basic', 'comfort', 'premium'));
exception when duplicate_object then null; end $$;

-- rang, prime (% de la valeur), franchise (% des réparations à la charge du joueur), remorquage gratuit
create or replace function private.insurance_plan(p_tier text) returns jsonb
language sql immutable as $$
  select case p_tier
    when 'none'    then '{"tier":"none","rank":0,"rate":0,"deductible":100,"towing":false}'::jsonb
    when 'basic'   then '{"tier":"basic","rank":1,"rate":2,"deductible":50,"towing":false}'::jsonb
    when 'comfort' then '{"tier":"comfort","rank":2,"rate":5,"deductible":20,"towing":true}'::jsonb
    when 'premium' then '{"tier":"premium","rank":3,"rate":9,"deductible":0,"towing":true}'::jsonb
  end $$;

create or replace function public.get_insurance_plans() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_agg(private.insurance_plan(t) order by private.insurance_plan(t) ->> 'rank')
    from unnest(array['none', 'basic', 'comfort', 'premium']) t $$;

create or replace function private.insurance_premium(p_tier text, p_value bigint) returns bigint
language sql immutable as $$ select ceil(p_value * (private.insurance_plan(p_tier) ->> 'rate')::numeric / 100)::bigint $$;

-- Changer le niveau d'un véhicule : monter = payer la prime du nouveau niveau ; descendre = gratuit (pas de remboursement).
create or replace function public.set_vehicle_insurance(p_vehicle_id uuid, p_insurance text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); g public.garage_vehicles; v_cost bigint := 0;
begin
  if private.insurance_plan(p_insurance) is null then raise exception 'bad_insurance'; end if;
  select * into g from public.garage_vehicles where id = p_vehicle_id and owner_id = v_me for update;
  if not found then raise exception 'not_found'; end if;
  if g.insurance = p_insurance then return jsonb_build_object('insurance', g.insurance, 'paid', 0); end if;
  if (private.insurance_plan(p_insurance) ->> 'rank')::int > (private.insurance_plan(g.insurance) ->> 'rank')::int then
    v_cost := private.insurance_premium(p_insurance, g.value);
    perform private.add_money(v_me, -v_cost, 'insurance', null, 'Assurance ' || p_insurance || ' : ' || coalesce(g.nickname, g.model_key));
  end if;
  update public.garage_vehicles set insurance = p_insurance where id = g.id;
  return jsonb_build_object('insurance', p_insurance, 'paid', v_cost);
end $$;

-- ------------------------------------------------------------------ négociation avec le concessionnaire
create table if not exists public.dealer_negotiations (
  user_id        uuid not null references public.profiles (id) on delete cascade,
  catalog_id     uuid not null references public.dealership_catalog (id) on delete cascade,
  list_price     bigint not null,
  floor_price    bigint not null,           -- secret : jamais renvoyé au client
  asking         bigint not null,           -- prix actuellement demandé par le vendeur
  patience       int not null,
  status         text not null default 'open' check (status in ('open', 'final', 'accepted', 'closed')),
  accepted_price bigint,
  offers         int not null default 0,
  updated_at     timestamptz not null default now(),
  expires_at     timestamptz not null,
  primary key (user_id, catalog_id)
);

create or replace function private.round50(x numeric) returns bigint language sql immutable as $$ select (round(x / 50) * 50)::bigint $$;

-- p_offer null = juste lire l'état (ou ouvrir la négociation). Réponse :
-- { status: open|counter|final|accepted|insulted|refused|closed, asking, list_price, patience, offers, message }
create or replace function public.negotiate_vehicle(p_catalog_id uuid, p_offer bigint default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  c public.dealership_catalog;
  n public.dealer_negotiations;
  v_reply text;
begin
  select * into c from public.dealership_catalog where id = p_catalog_id and enabled;
  if not found then raise exception 'not_found'; end if;
  select * into n from public.dealer_negotiations where user_id = v_me and catalog_id = c.id for update;
  -- rompue récemment : on attend avant de revenir à la charge
  if found and n.status = 'closed' and n.expires_at > now() then
    return jsonb_build_object('status', 'closed', 'asking', n.asking, 'list_price', n.list_price, 'patience', 0, 'offers', n.offers,
      'retry_at', n.expires_at);
  end if;
  if not found or n.expires_at <= now() or n.list_price <> c.price then
    delete from public.dealer_negotiations where user_id = v_me and catalog_id = c.id;
    insert into public.dealer_negotiations (user_id, catalog_id, list_price, floor_price, asking, patience, expires_at)
    values (v_me, c.id, c.price, private.round50(c.price * (0.80 + random() * 0.10)), c.price, 3 + floor(random() * 3)::int,
            now() + interval '20 minutes')
    returning * into n;
  end if;
  if p_offer is null or n.status = 'accepted' then
    return jsonb_build_object('status', n.status, 'asking', coalesce(n.accepted_price, n.asking), 'list_price', n.list_price,
      'patience', n.patience, 'offers', n.offers);
  end if;
  if p_offer <= 0 then raise exception 'bad_amount'; end if;
  n.offers := n.offers + 1;

  if p_offer >= n.asking then                                   -- offre au prix demandé (ou plus) : vendu
    n.status := 'accepted'; n.accepted_price := n.asking; v_reply := 'accepted';
  elsif p_offer < n.list_price * 0.60 then                      -- offre insultante : il coupe court
    n.status := 'closed'; n.expires_at := now() + interval '10 minutes'; v_reply := 'insulted';
  elsif p_offer >= n.floor_price and random() < 0.55 + 0.15 * (5 - n.patience) then -- assez proche : il accepte
    n.status := 'accepted'; n.accepted_price := private.round50(p_offer); v_reply := 'accepted';
  elsif n.status = 'final' then                                  -- il avait prévenu : dernier prix, à prendre ou à laisser
    n.status := 'closed'; n.expires_at := now() + interval '5 minutes'; v_reply := 'refused';
  else
    n.patience := n.patience - 1;
    -- contre-offre : il se rapproche de l'offre, jamais sous son plancher secret
    n.asking := greatest(n.floor_price, private.round50(n.asking - (n.asking - p_offer) * (0.25 + random() * 0.20)));
    if n.patience <= 0 then n.status := 'final'; v_reply := 'final'; else v_reply := 'counter'; end if;
  end if;
  n.updated_at := now();
  update public.dealer_negotiations set asking = n.asking, patience = n.patience, status = n.status, accepted_price = n.accepted_price,
         offers = n.offers, updated_at = n.updated_at, expires_at = n.expires_at
   where user_id = v_me and catalog_id = c.id;
  return jsonb_build_object('status', v_reply, 'asking', coalesce(n.accepted_price, n.asking), 'list_price', n.list_price,
    'patience', greatest(n.patience, 0), 'offers', n.offers);
end $$;

-- Achat : prix négocié accepté (encore valable) sinon prix affiché, + prime de l'assurance choisie.
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
  insert into public.garage_vehicles (owner_id, slot, model_key, config_key, color, value, insurance)
  values (v_me, v_slot, c.model_key, c.config_key, left(p_color, 40), c.price, coalesce(p_insurance, 'none')) returning id into v_id;
  delete from public.dealer_negotiations where user_id = v_me and catalog_id = c.id;
  return jsonb_build_object('vehicle_id', v_id, 'slot', v_slot, 'price', v_price, 'premium', v_prem);
end $$;

-- ------------------------------------------------------------------ get_me : + niveau d'assurance des véhicules
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

-- ------------------------------------------------------------------ droits
alter table public.dealer_negotiations enable row level security;
revoke all on public.dealer_negotiations from anon, authenticated;
grant all privileges on public.dealer_negotiations to postgres, service_role;
revoke all on function public.release_garage_spot(), public.get_insurance_plans(), public.set_vehicle_insurance(uuid, text),
  public.negotiate_vehicle(uuid, bigint), public.buy_vehicle_insured(uuid, text, text), public.get_me()
  from public, anon, authenticated;
grant execute on function public.release_garage_spot(), public.get_insurance_plans(), public.set_vehicle_insurance(uuid, text),
  public.negotiate_vehicle(uuid, bigint), public.buy_vehicle_insured(uuid, text, text), public.get_me()
  to authenticated;
