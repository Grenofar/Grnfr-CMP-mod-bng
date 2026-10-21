-- =====================================================================================
-- GRNFR Online - 0002 : serveurs de jeu (4 joueurs max), pseudo obligatoire et unique,
-- synchronisation des positions pour voir les autres joueurs et leur pseudo.
-- À exécuter APRÈS 0001_grnfr_online.sql (Supabase > SQL Editor > Run).
-- =====================================================================================

-- ------------------------------------------------------------------ pseudo obligatoire et unique
-- Plus de pseudo « généré » : une inscription avec un pseudo absent, invalide ou déjà pris est refusée.
-- (Le mod vérifie avant avec username_available ; ceci est le filet de sécurité côté base.)
create or replace function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_name  text := trim(coalesce(new.raw_user_meta_data ->> 'username', ''));
  v_start bigint := private.cfg('starting_money')::bigint;
begin
  if v_name !~ '^[A-Za-z0-9_]{3,20}$' then raise exception 'username_invalid'; end if;
  if exists (select 1 from public.profiles where lower(username) = lower(v_name)) then raise exception 'username_taken'; end if;
  begin
    insert into public.profiles (id, username, balance, garage_slots)
    values (new.id, v_name, v_start, private.cfg('garage_slots')::int);
  exception when unique_violation then raise exception 'username_taken';
  end;
  insert into public.transactions (user_id, kind, amount, balance_after, ref)
  values (new.id, 'signup', v_start, v_start, 'Argent de départ');
  return new;
end $$;

-- Comptes existants dont le pseudo a été généré automatiquement (player_xxxxxxxx) : ils doivent en choisir un.
alter table public.profiles add column if not exists username_confirmed boolean not null default true;
update public.profiles set username_confirmed = false
 where username = 'player_' || substr(replace(id::text, '-', ''), 1, 8) and username_confirmed;

create or replace function public.set_username(p_username text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user();
begin
  if p_username !~ '^[A-Za-z0-9_]{3,20}$' then raise exception 'username_invalid'; end if;
  if exists (select 1 from public.profiles where lower(username) = lower(p_username) and id <> v_me) then raise exception 'username_taken'; end if;
  if exists (select 1 from public.profiles where id = v_me and username_confirmed) then raise exception 'username_already_set'; end if;
  begin
    update public.profiles set username = p_username, username_confirmed = true where id = v_me;
  exception when unique_violation then raise exception 'username_taken';
  end;
end $$;

-- ------------------------------------------------------------------ réglages
insert into public.server_config (key, value, description) values
  ('member_timeout_seconds', '30',  'Un joueur sans signal depuis ce délai (s) libère sa place sur le serveur de jeu'),
  ('sync_interval_ms',       '300', 'Cadence d''envoi de la position au serveur (ms). Mini 150.')
on conflict (key) do nothing;

-- ------------------------------------------------------------------ tables
create table if not exists public.game_servers (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  max_players int  not null default 4 check (max_players between 1 and 16),
  created_at  timestamptz not null default now(),
  constraint game_servers_name check (char_length(name) between 2 and 40)
);
create unique index if not exists game_servers_name_lower on public.game_servers (lower(name));

-- Un joueur ne peut être que sur UN serveur à la fois (clé primaire = user_id).
create table if not exists public.server_members (
  user_id   uuid primary key references public.profiles (id) on delete cascade,
  server_id uuid not null references public.game_servers (id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  level     text,
  pos       jsonb,   -- {x,y,z}
  rot       jsonb,   -- [x,y,z,w] (quaternion)
  vel       jsonb,   -- [x,y,z]
  veh       jsonb    -- {model, config} : véhicule (ou personnage à pied) du joueur
);
create index if not exists server_members_server on public.server_members (server_id);

insert into public.game_servers (name, max_players)
select v.n, 4 from (values ('Serveur 1'), ('Serveur 2'), ('Serveur 3')) v(n)
where not exists (select 1 from public.game_servers);

-- ------------------------------------------------------------------ fonctions internes
create or replace function private.expire_members() returns void
language sql security definer set search_path = public, pg_temp as $$
  delete from public.server_members
   where last_seen < now() - make_interval(secs => greatest(10, coalesce(private.cfg('member_timeout_seconds'), 30))::int) $$;

-- tableau de n nombres (sinon null) ; borne les valeurs pour éviter les absurdités
create or replace function private.clean_arr(p jsonb, n int) returns jsonb
language plpgsql immutable as $$
declare v jsonb := '[]'::jsonb; i int; x float8;
begin
  if p is null or jsonb_typeof(p) <> 'array' or jsonb_array_length(p) <> n then return null; end if;
  for i in 0 .. n - 1 loop
    if jsonb_typeof(p -> i) <> 'number' then return null; end if;
    x := (p ->> i)::float8;
    if x <> x or abs(x) > 100000 then return null; end if;
    v := v || to_jsonb(round(x::numeric, 3));
  end loop;
  return v;
end $$;

create or replace function private.clean_veh(p jsonb) returns jsonb
language sql immutable as $$
  select case
    when p is null or jsonb_typeof(p) <> 'object' then null
    when coalesce(p ->> 'model', '') !~ '^[A-Za-z0-9_.-]{1,60}$' then null
    else jsonb_strip_nulls(jsonb_build_object('model', p ->> 'model',
           'config', case when coalesce(p ->> 'config', '') ~ '^[A-Za-z0-9_.-]{1,60}$' then p ->> 'config' end))
  end $$;

-- ------------------------------------------------------------------ RPC publiques
-- Liste des serveurs : joueurs présents (pseudos) et places restantes.
create or replace function public.get_servers() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user();
begin
  perform private.expire_members();
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', s.id, 'name', s.name, 'max_players', s.max_players,
      'count', (select count(*) from public.server_members m where m.server_id = s.id),
      'players', coalesce((select jsonb_agg(p.username order by m.joined_at)
                             from public.server_members m join public.profiles p on p.id = m.user_id
                            where m.server_id = s.id), '[]'::jsonb),
      'joined', exists (select 1 from public.server_members m where m.server_id = s.id and m.user_id = v_me)
    ) order by s.name) from public.game_servers s), '[]'::jsonb);
end $$;

-- Rejoindre un serveur : pseudo choisi obligatoire, 4 joueurs maximum (limite appliquée sous verrou).
create or replace function public.join_server(p_server uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_srv public.game_servers;
  v_prof public.profiles;
  v_n int;
begin
  select * into v_prof from public.profiles where id = v_me;
  if v_prof.id is null or v_prof.username !~ '^[A-Za-z0-9_]{3,20}$' or not v_prof.username_confirmed then
    raise exception 'username_required';
  end if;
  select * into v_srv from public.game_servers where id = p_server for update;  -- sérialise les arrivées
  if v_srv.id is null then raise exception 'server_not_found'; end if;
  perform private.expire_members();
  if exists (select 1 from public.server_members where user_id = v_me and server_id = v_srv.id) then
    update public.server_members set last_seen = now() where user_id = v_me;      -- déjà dedans : OK
  else
    select count(*) into v_n from public.server_members where server_id = v_srv.id;
    if v_n >= v_srv.max_players then raise exception 'server_full'; end if;
    delete from public.server_members where user_id = v_me;                         -- quitte l'ancien serveur
    insert into public.server_members (user_id, server_id) values (v_me, v_srv.id);
  end if;
  return jsonb_build_object('id', v_srv.id, 'name', v_srv.name, 'max_players', v_srv.max_players);
end $$;

create or replace function public.leave_server() returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user();
begin delete from public.server_members where user_id = v_me; end $$;

-- Un seul appel pour envoyer sa position ET recevoir celle des autres joueurs du même serveur
-- (position {x,y,z}, rot [x,y,z,w], vel [x,y,z], veh {model,config}). Aussi un battement de cœur.
create or replace function public.server_sync(p_level text, p_pos jsonb, p_rot jsonb, p_vel jsonb, p_veh jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_srv uuid;
  v_name text; v_max int;
begin
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
  select name, max_players into v_name, v_max from public.game_servers where id = v_srv;
  return jsonb_build_object(
    'server', jsonb_build_object('id', v_srv, 'name', v_name, 'max_players', v_max),
    'players', coalesce((
      select jsonb_agg(jsonb_build_object('username', p.username, 'level', m.level, 'pos', m.pos, 'rot', m.rot,
                                          'vel', m.vel, 'veh', m.veh) order by m.joined_at)
        from public.server_members m join public.profiles p on p.id = m.user_id
       where m.server_id = v_srv and m.user_id <> v_me
         and m.last_seen > now() - make_interval(secs => greatest(10, coalesce(private.cfg('member_timeout_seconds'), 30))::int)
    ), '[]'::jsonb));
end $$;

-- ------------------------------------------------------------------ administration
create or replace function public.admin_create_server(p_name text, p_max int default 4) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid;
begin
  perform private.require_admin();
  insert into public.game_servers (name, max_players) values (trim(p_name), coalesce(p_max, 4)) returning id into v_id;
  return v_id;
end $$;

create or replace function public.admin_kick(p_username text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform private.require_admin();
  delete from public.server_members where user_id = (select id from public.profiles where lower(username) = lower(p_username));
end $$;

-- Garage visible d'un autre joueur (pour lui proposer un échange). Seulement les véhicules non mis en annonce.
create or replace function public.get_player_garage(p_username text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'slot', g.slot, 'model_key', g.model_key,
              'config_key', g.config_key, 'nickname', g.nickname, 'value', g.value) order by g.slot)
            from public.garage_vehicles g join public.profiles p on p.id = g.owner_id
           where lower(p.username) = lower(p_username)
             and not exists (select 1 from public.listings l where l.vehicle_id = g.id and l.status = 'open')), '[]'::jsonb);
end $$;

-- ------------------------------------------------------------------ droits
alter table public.game_servers  enable row level security;
alter table public.server_members enable row level security;
revoke all on public.game_servers, public.server_members from anon, authenticated;
revoke all on function
  public.set_username(text), public.get_servers(), public.join_server(uuid), public.leave_server(),
  public.server_sync(text, jsonb, jsonb, jsonb, jsonb), public.admin_create_server(text, int), public.admin_kick(text), public.get_player_garage(text)
  from public, anon, authenticated;
grant execute on function
  public.set_username(text), public.get_servers(), public.join_server(uuid), public.leave_server(),
  public.server_sync(text, jsonb, jsonb, jsonb, jsonb), public.admin_create_server(text, int), public.admin_kick(text), public.get_player_garage(text)
  to authenticated;
