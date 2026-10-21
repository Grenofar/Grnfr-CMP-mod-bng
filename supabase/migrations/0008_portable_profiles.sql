-- =====================================================================================
-- GRNFR Online - 0008 : comptes "pseudo seulement" (profil portable) + anti-partage de compte.
-- À exécuter APRÈS 0001-0007 (Supabase > SQL Editor > Run).
-- Nécessite aussi : Authentication > Providers > Anonymous Sign-Ins → activé (désactivé par défaut).
--
-- Un compte peut maintenant être créé sans e-mail (connexion anonyme Supabase) : le joueur ne choisit
-- qu'un pseudo. Ce qui identifie vraiment le joueur, c'est le jeton de connexion que l'interface garde déjà
-- (voir net.js) : "exporter son profil" (garage.lua... non, profile.lua côté mod) ne fait qu'écrire ce jeton
-- dans un fichier sur cette machine, à copier (clé USB, etc.) sur une autre pour s'y reconnecter. Rien de
-- ça ne touche à l'argent ou au garage, qui restent décidés par le serveur, pas par le fichier exporté.
--
-- Anti-partage : à chaque connexion, un nouveau session_token aléatoire est enregistré. Toute requête
-- authentifiée qui présente un session_token différent de celui enregistré prouve qu'une autre connexion
-- a eu lieu depuis (le même profil utilisé ailleurs) : elle est refusée ('session_replaced'), ce qui
-- déconnecte cette session au prochain battement de cœur. La connexion la plus récente n'est jamais gênée.
-- =====================================================================================

alter table public.profiles add column if not exists session_token uuid;

-- Remplace handle_new_user (0002) : un pseudo absent (connexion anonyme) reçoit un nom temporaire non
-- confirmé, comme les anciens comptes générés — le joueur choisit son vrai pseudo avec set_username.
-- Un pseudo fourni mais invalide ou déjà pris continue d'être refusé immédiatement.
create or replace function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_raw       text := trim(coalesce(new.raw_user_meta_data ->> 'username', ''));
  v_name      text;
  v_confirmed boolean;
  v_start     bigint := private.cfg('starting_money')::bigint;
begin
  if v_raw = '' then
    v_name := 'profile_' || substr(replace(new.id::text, '-', ''), 1, 10);
    v_confirmed := false;
  else
    if v_raw !~ '^[A-Za-z0-9_]{3,20}$' then raise exception 'username_invalid'; end if;
    if exists (select 1 from public.profiles where lower(username) = lower(v_raw)) then raise exception 'username_taken'; end if;
    v_name := v_raw;
    v_confirmed := true;
  end if;
  begin
    insert into public.profiles (id, username, balance, garage_slots, username_confirmed)
    values (new.id, v_name, v_start, private.cfg('garage_slots')::int, v_confirmed);
  exception when unique_violation then raise exception 'username_taken';
  end;
  insert into public.transactions (user_id, kind, amount, balance_after, ref)
  values (new.id, 'signup', v_start, v_start, 'Argent de départ');
  return new;
end $$;

-- Nouveau jeton de session, à appeler juste après connexion (avant le premier heartbeat/server_sync).
create or replace function public.start_session() returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_tok uuid := gen_random_uuid();
begin
  update public.profiles set session_token = v_tok where id = v_me;
  return v_tok;
end $$;

-- p_session = null : compatibilité (vieux client, ou appel qui ne vérifie pas) : pas de contrôle.
create or replace function private.check_session(p_me uuid, p_session uuid) returns void
language plpgsql as $$
declare v_cur uuid;
begin
  if p_session is null then return; end if;
  select session_token into v_cur from public.profiles where id = p_me;
  if v_cur is not null and v_cur <> p_session then raise exception 'session_replaced'; end if;
end $$;

-- Identique à l'original (0001), avec un seul ajout : profile.username_confirmed (pour que l'interface
-- propose de choisir un pseudo juste après une connexion anonyme).
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

drop function if exists public.heartbeat(text, jsonb, text);
create or replace function public.heartbeat(p_level text default null, p_pos jsonb default null, p_duty text default null, p_session uuid default null)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_bal bigint;
begin
  perform private.check_session(v_me, p_session);
  if p_duty is not null and p_duty not in ('taxi', 'bus', 'none') then raise exception 'bad_duty'; end if;
  update public.profiles set
      last_seen = now(),
      level = coalesce(left(p_level, 60), level),
      pos = case when private.valid_pos(p_pos) then private.clean_pos(p_pos) else pos end,
      duty = case when p_duty is null then duty when p_duty = 'none' then null else p_duty end
   where id = v_me returning balance into v_bal;
  return v_bal;
end $$;

drop function if exists public.server_sync(text, jsonb, jsonb, jsonb, jsonb, jsonb);
create or replace function public.server_sync(p_level text, p_pos jsonb, p_rot jsonb, p_vel jsonb, p_veh jsonb, p_convoy jsonb default null, p_session uuid default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_srv uuid;
  v_name text; v_max int;
  v_host uuid;
  v_is_host boolean;
  v_convoy jsonb;
begin
  perform private.check_session(v_me, p_session);
  update public.server_members set
      last_seen = now(),
      level = coalesce(left(p_level, 60), level),
      pos = case when private.valid_pos(p_pos) then private.clean_pos(p_pos) else pos end,
      rot = coalesce(private.clean_arr(p_rot, 4), rot),
      vel = coalesce(private.clean_arr(p_vel, 3), vel),
      veh = coalesce(private.clean_veh(p_veh), veh)
   where user_id = v_me returning server_id into v_srv;
  if v_srv is null then raise exception 'not_in_server'; end if;
  update public.profiles set last_seen = now(),
      level = coalesce(left(p_level, 60), level),
      pos = case when private.valid_pos(p_pos) then private.clean_pos(p_pos) else pos end
   where id = v_me;
  perform private.expire_members();
  select m.user_id into v_host from public.server_members m where m.server_id = v_srv order by m.joined_at asc limit 1;
  v_is_host := (v_host = v_me);
  if v_is_host and p_convoy is not null then
    update public.game_servers set convoy = private.clean_convoy(p_convoy) where id = v_srv returning convoy into v_convoy;
  else
    select convoy into v_convoy from public.game_servers where id = v_srv;
  end if;
  select name, max_players into v_name, v_max from public.game_servers where id = v_srv;
  return jsonb_build_object(
    'server', jsonb_build_object('id', v_srv, 'name', v_name, 'max_players', v_max),
    'is_host', v_is_host,
    'convoy', v_convoy,
    'players', coalesce((
      select jsonb_agg(jsonb_build_object('username', p.username, 'level', m.level, 'pos', m.pos, 'rot', m.rot,
                                          'vel', m.vel, 'veh', m.veh) order by m.joined_at)
        from public.server_members m join public.profiles p on p.id = m.user_id
       where m.server_id = v_srv and m.user_id <> v_me
         and m.last_seen > now() - make_interval(secs => greatest(10, coalesce(private.cfg('member_timeout_seconds'), 30))::int)
    ), '[]'::jsonb));
end $$;

revoke all on function public.start_session(), public.heartbeat(text, jsonb, text, uuid), public.server_sync(text, jsonb, jsonb, jsonb, jsonb, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.start_session(), public.heartbeat(text, jsonb, text, uuid), public.server_sync(text, jsonb, jsonb, jsonb, jsonb, jsonb, uuid)
  to authenticated;
