-- =====================================================================================
-- GRNFR Online - 0019 : vente de pièces entre joueurs, à prix libre (TODO point 2quinquies de CLAUDE.md).
-- À exécuter APRÈS 0001-0018.
--
-- Une pièce retirée d'un véhicule (remove_vehicle_part, 0018) ne disparaissait plus : elle va maintenant dans
-- un "stock de pièces détachées" du joueur (garage_spare_parts), comme les véhicules rangés. De là, elle peut
-- être : installée sur un AUTRE véhicule du même modèle (install_spare_part, gratuit, la pièce est déjà payée),
-- ou mise en vente à un prix choisi par le vendeur (create_part_listing/buy_part_listing — même principe que
-- listings/buy_listing pour les véhicules : prix toujours décidé par le VENDEUR, jamais inventé par le serveur,
-- mais le serveur ne fait que déplacer la pièce et l'argent, jamais créer de valeur).
-- =====================================================================================

create table if not exists public.garage_spare_parts (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  model_key  text not null,
  slot       text not null,
  part_key   text not null,
  name       text not null,
  value      bigint not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists spare_parts_owner on public.garage_spare_parts (owner_id);

create table if not exists public.part_listings (
  id          uuid primary key default gen_random_uuid(),
  seller_id   uuid not null references public.profiles (id) on delete cascade,
  spare_id    uuid not null references public.garage_spare_parts (id) on delete cascade,
  model_key   text not null,
  slot        text not null,
  part_key    text not null,
  name        text not null,
  price       bigint not null check (price > 0),
  description text,
  status      text not null default 'open' check (status in ('open', 'sold', 'cancelled')),
  buyer_id    uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  sold_at     timestamptz
);
create unique index if not exists part_listings_one_open_per_spare on public.part_listings (spare_id) where status = 'open';
create index if not exists part_listings_open on public.part_listings (status, created_at desc);

-- Retrait d'une pièce : va maintenant dans le stock de pièces détachées (plus de perte sèche). Si c'était un
-- module de stockage, la capacité cargo du véhicule redescend à 0 (inchangé par rapport à 0018).
create or replace function public.remove_vehicle_part(p_vehicle_id uuid, p_slot text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); g public.garage_vehicles; v_part jsonb; v_cat public.vehicle_parts_catalog;
begin
  select * into g from public.garage_vehicles where id = p_vehicle_id and owner_id = v_me for update;
  if not found then raise exception 'not_found'; end if;
  v_part := g.parts -> p_slot;
  if v_part is null then raise exception 'not_found'; end if;
  select * into v_cat from public.vehicle_parts_catalog
   where model_key = g.model_key and slot = p_slot and part_key = (v_part ->> 'part_key');
  insert into public.garage_spare_parts (owner_id, model_key, slot, part_key, name, value)
  values (v_me, g.model_key, p_slot, v_part ->> 'part_key', coalesce(v_part ->> 'name', v_part ->> 'part_key'),
          coalesce((v_part ->> 'price')::bigint, 0));
  update public.garage_vehicles set parts = parts - p_slot,
         cargo_capacity = case when v_cat.cargo_units is not null then 0 else cargo_capacity end
   where id = g.id returning parts, cargo_capacity into g.parts, g.cargo_capacity;
  return jsonb_build_object('parts', g.parts, 'cargo_capacity', g.cargo_capacity);
end $$;

-- Mes pièces de rechange (stock, pas encore vendues).
create or replace function public.get_my_spare_parts() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'model_key', model_key, 'slot', slot, 'part_key', part_key,
           'name', name, 'value', value) order by created_at desc), '[]'::jsonb)
    from public.garage_spare_parts where owner_id = auth.uid() $$;

-- Installe une pièce de rechange sur un de mes véhicules du MÊME modèle (gratuit : déjà payée une fois).
create or replace function public.install_spare_part(p_spare_id uuid, p_vehicle_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); sp public.garage_spare_parts; g public.garage_vehicles; v_cat public.vehicle_parts_catalog;
begin
  select * into sp from public.garage_spare_parts where id = p_spare_id and owner_id = v_me for update;
  if not found then raise exception 'not_found'; end if;
  select * into g from public.garage_vehicles where id = p_vehicle_id and owner_id = v_me for update;
  if not found then raise exception 'not_found'; end if;
  if g.model_key <> sp.model_key then raise exception 'wrong_model'; end if;
  select * into v_cat from public.vehicle_parts_catalog where model_key = sp.model_key and slot = sp.slot and part_key = sp.part_key;
  update public.garage_vehicles
     set parts = parts || jsonb_build_object(sp.slot, jsonb_build_object('part_key', sp.part_key, 'name', sp.name, 'price', sp.value)),
         cargo_capacity = case when v_cat.cargo_units is not null then v_cat.cargo_units else cargo_capacity end
   where id = g.id
   returning parts, cargo_capacity into g.parts, g.cargo_capacity;
  delete from public.garage_spare_parts where id = sp.id;
  return jsonb_build_object('parts', g.parts, 'cargo_capacity', g.cargo_capacity);
end $$;

-- Mise en vente, à un prix choisi par le vendeur (même plafond que les annonces de véhicules).
create or replace function public.create_part_listing(p_spare_id uuid, p_price bigint, p_description text default null) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); sp public.garage_spare_parts; v_id uuid;
begin
  if p_price is null or p_price <= 0 then raise exception 'bad_amount'; end if;
  if p_price > private.cfg('max_listing_price') then raise exception 'over_limit'; end if;
  select * into sp from public.garage_spare_parts where id = p_spare_id and owner_id = v_me for update;
  if not found then raise exception 'not_found'; end if;
  if exists (select 1 from public.part_listings where spare_id = p_spare_id and status = 'open') then raise exception 'already_listed'; end if;
  insert into public.part_listings (seller_id, spare_id, model_key, slot, part_key, name, price, description)
  values (v_me, sp.id, sp.model_key, sp.slot, sp.part_key, sp.name, p_price, left(p_description, 200))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.cancel_part_listing(p_listing_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user();
begin
  update public.part_listings set status = 'cancelled' where id = p_listing_id and seller_id = v_me and status = 'open';
  if not found then raise exception 'not_found'; end if;
end $$;

create or replace function public.get_part_market(p_limit int default 50, p_offset int default 0) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'model_key', l.model_key, 'slot', l.slot, 'part_key', l.part_key,
           'name', l.name, 'price', l.price, 'description', l.description, 'seller', p.username, 'seller_id', l.seller_id,
           'created_at', l.created_at) order by l.created_at desc), '[]'::jsonb)
    from (select * from public.part_listings where status = 'open' order by created_at desc
           limit greatest(1, least(coalesce(p_limit, 50), 100)) offset greatest(coalesce(p_offset, 0), 0)) l
    join public.profiles p on p.id = l.seller_id $$;

-- Achat : la pièce rejoint le stock de pièces détachées de l'acheteur (il l'installe ensuite où il veut avec
-- install_spare_part) ; même commission que le marché de véhicules (market_fee_percent).
create or replace function public.buy_part_listing(p_listing_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); l public.part_listings; v_fee bigint; v_seller_name text; v_spare_id uuid;
begin
  select * into l from public.part_listings where id = p_listing_id for update;
  if not found or l.status <> 'open' then raise exception 'listing_unavailable'; end if;
  if l.seller_id = v_me then raise exception 'own_listing'; end if;
  perform private.lock_two(v_me, l.seller_id);
  perform 1 from public.garage_spare_parts where id = l.spare_id and owner_id = l.seller_id for update;
  if not found then raise exception 'listing_unavailable'; end if;
  v_fee := floor(l.price * private.cfg('market_fee_percent') / 100.0);
  select username into v_seller_name from public.profiles where id = l.seller_id;
  perform private.add_money(v_me, -l.price, 'market_purchase', l.seller_id, 'Pièce achetée à ' || v_seller_name);
  perform private.add_money(l.seller_id, l.price - v_fee, 'market_sale', v_me, 'Pièce vendue (commission ' || v_fee || ')');
  update public.garage_spare_parts set owner_id = v_me where id = l.spare_id returning id into v_spare_id;
  update public.part_listings set status = 'sold', buyer_id = v_me, sold_at = now() where id = l.id;
  return jsonb_build_object('spare_id', v_spare_id, 'price', l.price);
end $$;

-- ------------------------------------------------------------------ droits
alter table public.garage_spare_parts enable row level security;
revoke all on public.garage_spare_parts from anon, authenticated;
grant all privileges on public.garage_spare_parts to postgres, service_role;
alter table public.part_listings enable row level security;
revoke all on public.part_listings from anon, authenticated;
grant all privileges on public.part_listings to postgres, service_role;

revoke all on function public.get_my_spare_parts(), public.install_spare_part(uuid, uuid),
  public.create_part_listing(uuid, bigint, text), public.cancel_part_listing(uuid),
  public.get_part_market(int, int), public.buy_part_listing(uuid)
  from public, anon, authenticated;
grant execute on function public.get_my_spare_parts(), public.install_spare_part(uuid, uuid),
  public.create_part_listing(uuid, bigint, text), public.cancel_part_listing(uuid),
  public.get_part_market(int, int), public.buy_part_listing(uuid)
  to authenticated;
