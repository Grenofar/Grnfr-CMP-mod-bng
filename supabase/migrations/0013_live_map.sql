-- =====================================================================================
-- GRNFR Online - 0013 : carte en direct (app GRNFR Host CMP).
-- À exécuter APRÈS 0001-0012.
--
-- * level_maps : le réseau routier d'une carte, vu de dessus (segments 2D [x1,y1,x2,y2] en mètres, arrondis).
--   Envoyé UNE fois par carte par le mod d'un joueur qui s'y trouve (lu dans le jeu : map.getMap()), puis relu
--   par l'app host pour dessiner la carte. Aucune image du jeu : juste les routes, tracées par l'app.
-- * live_servers() : serveurs de jeu du mod (Serveur 1, 2, 3...) avec, pour chaque joueur présent, sa carte,
--   sa position 2D, son véhicule et son service. Public (anon) : c'est l'affichage d'une carte en direct,
--   comme une liste de serveurs ; rien d'autre (ni argent, ni id) n'est exposé.
-- =====================================================================================

create table if not exists public.level_maps (
  level       text primary key check (level ~ '^[A-Za-z0-9_-]{1,60}$'),
  roads       jsonb not null,             -- [[x1,y1,x2,y2], ...]
  bounds      jsonb not null,             -- {minx,miny,maxx,maxy}
  segments    int not null,
  uploaded_by uuid references public.profiles (id) on delete set null,
  updated_at  timestamptz not null default now()
);

-- Le mod envoie les routes de sa carte si elles manquent (ou ont plus de 30 jours). Taille bornée.
create or replace function public.upload_level_roads(p_level text, p_roads jsonb) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_n int;
  v_b jsonb;
begin
  if p_level is null or p_level !~ '^[A-Za-z0-9_-]{1,60}$' then raise exception 'bad_level'; end if;
  if exists (select 1 from public.level_maps where level = p_level and updated_at > now() - interval '30 days') then return false; end if;
  if p_roads is null or jsonb_typeof(p_roads) <> 'array' then raise exception 'bad_roads'; end if;
  v_n := jsonb_array_length(p_roads);
  if v_n < 10 or v_n > 60000 or pg_column_size(p_roads) > 4000000 then raise exception 'bad_roads'; end if;
  if exists (select 1 from jsonb_array_elements(p_roads) e
              where jsonb_typeof(e) <> 'array' or jsonb_array_length(e) <> 4
                 or exists (select 1 from jsonb_array_elements(e) x where jsonb_typeof(x) <> 'number' or abs((x #>> '{}')::float8) > 100000)) then
    raise exception 'bad_roads';
  end if;
  select jsonb_build_object('minx', min(least((e->>0)::float8, (e->>2)::float8)), 'miny', min(least((e->>1)::float8, (e->>3)::float8)),
                            'maxx', max(greatest((e->>0)::float8, (e->>2)::float8)), 'maxy', max(greatest((e->>1)::float8, (e->>3)::float8)))
    into v_b from jsonb_array_elements(p_roads) e;
  insert into public.level_maps (level, roads, bounds, segments, uploaded_by, updated_at)
  values (p_level, p_roads, v_b, v_n, v_me, now())
  on conflict (level) do update set roads = excluded.roads, bounds = excluded.bounds, segments = excluded.segments,
    uploaded_by = excluded.uploaded_by, updated_at = now();
  return true;
end $$;

-- Le mod demande seulement s'il doit envoyer (évite d'envoyer des centaines de Ko pour rien).
create or replace function public.level_roads_needed(p_level text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select not exists (select 1 from public.level_maps where level = p_level and updated_at > now() - interval '30 days') $$;

create or replace function public.get_level_roads(p_level text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('level', level, 'roads', roads, 'bounds', bounds, 'segments', segments, 'updated_at', updated_at)
    from public.level_maps where level = p_level $$;

create or replace function public.live_servers() returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id, 'name', s.name, 'max_players', s.max_players,
      'players', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'username', p.username, 'level', m.level,
                 'x', (m.pos ->> 'x')::float8, 'y', (m.pos ->> 'y')::float8,
                 'veh', m.veh ->> 'model', 'duty', p.duty, 'since', m.joined_at) order by m.joined_at)
          from public.server_members m join public.profiles p on p.id = m.user_id
         where m.server_id = s.id
           and m.last_seen > now() - make_interval(secs => greatest(10, coalesce(private.cfg('member_timeout_seconds'), 30))::int)
      ), '[]'::jsonb)
    ) order by s.name), '[]'::jsonb)
  from public.game_servers s $$;

alter table public.level_maps enable row level security;
revoke all on public.level_maps from anon, authenticated;
revoke all on function public.upload_level_roads(text, jsonb), public.level_roads_needed(text), public.get_level_roads(text), public.live_servers()
  from public, anon, authenticated;
grant execute on function public.upload_level_roads(text, jsonb), public.level_roads_needed(text) to authenticated;
grant execute on function public.get_level_roads(text), public.live_servers() to anon, authenticated;
