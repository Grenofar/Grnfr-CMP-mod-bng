-- =====================================================================================
-- GRNFR Online - 0015 : ordinateur du garage = personnalisation du véhicule (TODO point 1 de CLAUDE.md).
-- À exécuter APRÈS 0001-0014.
--
-- Il n'existe aucun catalogue réel des pièces BeamNG côté serveur (des milliers de pièces par véhicule, dans les
-- fichiers jbeam du jeu) : le serveur ne connaît donc que des CATÉGORIES de modification (chacune avec son propre
-- pourcentage de la valeur du véhicule, comme private.insurance_plan dans 0014) et calcule lui-même le prix — jamais
-- un prix envoyé par le client. "slot" et "part_name" sont de simples libellés choisis par le mod (Lua), enregistrés
-- tels quels pour réaffichage et pour que le mod retente d'appliquer la pièce en jeu ; le serveur ne les comprend pas.
-- * parts  jsonb : { "<slot>": { "category", "part_name", "price" } } — pièces/perfs achetées.
-- * tuning jsonb : réglages numériques (hauteur de caisse, pression des pneus...) — gratuit, juste enregistré.
-- * paint  jsonb : couleurs choisies (jusqu'à 3 couches, comme le jeu) — payant (catégorie "paint").
-- * cargo_capacity int : unités de stockage ajoutées (servira à la phase 2, capacité de colis) — payant par unité.
-- Tout ça survit au rangement de la voiture (colonnes de garage_vehicles, pas un état en jeu).
-- =====================================================================================

alter table public.garage_vehicles add column if not exists parts jsonb not null default '{}'::jsonb;
alter table public.garage_vehicles add column if not exists tuning jsonb not null default '{}'::jsonb;
alter table public.garage_vehicles add column if not exists paint jsonb;
alter table public.garage_vehicles add column if not exists cargo_capacity int not null default 0 check (cargo_capacity >= 0);

-- rang jamais utilisé pour autre chose que l'affichage ; rate = % de la valeur du véhicule, par achat.
create or replace function private.part_rate(p_category text) returns numeric
language sql immutable as $$
  select case p_category
    when 'cosmetic'    then 3
    when 'performance' then 6
    when 'suspension'  then 4
    when 'paint'       then 2
    when 'cargo'       then 5
  end $$;

create or replace function private.part_price(p_category text, p_value bigint) returns bigint
language sql immutable as $$ select greatest(200, ceil(coalesce(p_value, 0) * private.part_rate(p_category) / 100))::bigint $$;

create or replace function public.get_part_categories() returns jsonb
language sql stable as $$
  select jsonb_agg(jsonb_build_object('category', c, 'rate', private.part_rate(c)))
    from unnest(array['cosmetic', 'performance', 'suspension', 'paint', 'cargo']) c $$;

-- Achat d'une pièce/amélioration dans une catégorie, pour un emplacement donné (remplace l'ancienne pièce du même
-- emplacement s'il y en avait une — pas de remboursement de l'ancienne, pour éviter d'acheter-revendre en boucle).
create or replace function public.buy_vehicle_part(p_vehicle_id uuid, p_category text, p_slot text, p_part_name text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); g public.garage_vehicles; v_price bigint;
begin
  if private.part_rate(p_category) is null then raise exception 'bad_category'; end if;
  if coalesce(p_slot, '') = '' then raise exception 'bad_slot'; end if;
  select * into g from public.garage_vehicles where id = p_vehicle_id and owner_id = v_me for update;
  if not found then raise exception 'not_found'; end if;
  v_price := private.part_price(p_category, g.value);
  perform private.add_money(v_me, -v_price, 'vehicle_part', null, coalesce(p_part_name, p_category),
    jsonb_build_object('vehicle_id', g.id, 'slot', p_slot, 'category', p_category));
  update public.garage_vehicles set parts = parts || jsonb_build_object(p_slot,
      jsonb_build_object('category', p_category, 'part_name', left(coalesce(p_part_name, ''), 60), 'price', v_price))
   where id = g.id
   returning parts into g.parts;
  return jsonb_build_object('price', v_price, 'parts', g.parts);
end $$;

-- Retrait d'une pièce (retour à l'emplacement d'origine) : gratuit, pas de remboursement.
create or replace function public.remove_vehicle_part(p_vehicle_id uuid, p_slot text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); g public.garage_vehicles;
begin
  select * into g from public.garage_vehicles where id = p_vehicle_id and owner_id = v_me for update;
  if not found then raise exception 'not_found'; end if;
  update public.garage_vehicles set parts = parts - coalesce(p_slot, '') where id = g.id returning parts into g.parts;
  return jsonb_build_object('parts', g.parts);
end $$;

-- Réglages (tuning) : gratuit, juste enregistré pour que le mod les réapplique au véhicule.
create or replace function public.save_vehicle_tuning(p_vehicle_id uuid, p_tuning jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); g public.garage_vehicles;
begin
  if jsonb_typeof(p_tuning) is distinct from 'object' then raise exception 'bad_tuning'; end if;
  select * into g from public.garage_vehicles where id = p_vehicle_id and owner_id = v_me for update;
  if not found then raise exception 'not_found'; end if;
  update public.garage_vehicles set tuning = p_tuning where id = g.id;
  return jsonb_build_object('tuning', p_tuning);
end $$;

-- Peinture : payant (catégorie "paint"), p_paint = tableau de 1 à 3 couches { r, g, b, a, metallic? } (comme le jeu).
create or replace function public.repaint_vehicle(p_vehicle_id uuid, p_paint jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); g public.garage_vehicles; v_price bigint;
begin
  if jsonb_typeof(p_paint) is distinct from 'array' or jsonb_array_length(p_paint) not between 1 and 3 then raise exception 'bad_paint'; end if;
  select * into g from public.garage_vehicles where id = p_vehicle_id and owner_id = v_me for update;
  if not found then raise exception 'not_found'; end if;
  v_price := private.part_price('paint', g.value);
  perform private.add_money(v_me, -v_price, 'vehicle_paint', null, coalesce(g.nickname, g.model_key),
    jsonb_build_object('vehicle_id', g.id));
  update public.garage_vehicles set paint = p_paint where id = g.id;
  return jsonb_build_object('price', v_price, 'paint', p_paint);
end $$;

-- Espace de stockage : chaque achat ajoute p_capacity unités (1 à 5 d'un coup, 20 unités max par véhicule au total),
-- prix = catégorie "cargo" multipliée par le nombre d'unités demandées.
create or replace function public.buy_cargo_module(p_vehicle_id uuid, p_capacity int) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); g public.garage_vehicles; v_price bigint;
begin
  if coalesce(p_capacity, 0) not between 1 and 5 then raise exception 'bad_capacity'; end if;
  select * into g from public.garage_vehicles where id = p_vehicle_id and owner_id = v_me for update;
  if not found then raise exception 'not_found'; end if;
  if g.cargo_capacity + p_capacity > 20 then raise exception 'cargo_max'; end if;
  v_price := private.part_price('cargo', g.value) * p_capacity;
  perform private.add_money(v_me, -v_price, 'vehicle_cargo', null, coalesce(g.nickname, g.model_key),
    jsonb_build_object('vehicle_id', g.id, 'capacity', p_capacity));
  update public.garage_vehicles set cargo_capacity = cargo_capacity + p_capacity where id = g.id returning cargo_capacity into g.cargo_capacity;
  return jsonb_build_object('price', v_price, 'cargo_capacity', g.cargo_capacity);
end $$;

-- ------------------------------------------------------------------ get_me : + personnalisation des véhicules
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
         order by r.created_at desc limit 1) x)
  ) into v_out;
  return v_out;
end $$;

-- ------------------------------------------------------------------ droits
revoke all on function public.get_part_categories(), public.buy_vehicle_part(uuid, text, text, text),
  public.remove_vehicle_part(uuid, text), public.save_vehicle_tuning(uuid, jsonb), public.repaint_vehicle(uuid, jsonb),
  public.buy_cargo_module(uuid, int), public.get_me()
  from public, anon, authenticated;
grant execute on function public.get_part_categories(), public.buy_vehicle_part(uuid, text, text, text),
  public.remove_vehicle_part(uuid, text), public.save_vehicle_tuning(uuid, jsonb), public.repaint_vehicle(uuid, jsonb),
  public.buy_cargo_module(uuid, int), public.get_me()
  to authenticated;
