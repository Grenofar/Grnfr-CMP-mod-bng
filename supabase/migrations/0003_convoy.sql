-- =====================================================================================
-- GRNFR Online - 0003 : trafic partagé (2 voitures IA) par serveur de jeu.
-- À exécuter APRÈS 0001_grnfr_online.sql et 0002_game_servers.sql (Supabase > SQL Editor > Run).
--
-- Principe : sur chaque serveur de jeu, le joueur présent depuis le plus longtemps ("hôte", calculé à
-- chaque appel à partir de server_members.joined_at : aucune table "qui est hôte" n'est nécessaire)
-- fait rouler 2 voitures IA et envoie leur position via server_sync, comme pour sa propre position.
-- Les autres joueurs reçoivent cette position et affichent 2 fantômes (comme pour les autres joueurs),
-- sans collision, sans y toucher. Si l'hôte quitte le serveur, le joueur suivant par ancienneté devient
-- hôte au prochain appel de server_sync et fait apparaître ses propres voitures de trafic à sa place.
-- =====================================================================================

alter table public.game_servers add column if not exists convoy jsonb;

-- Garde au plus 2 voitures, chacune avec une position valide et un véhicule reconnu ; ignore le reste
-- (pas d'hôte légitime, ou données absurdes).
create or replace function private.clean_convoy(p jsonb) returns jsonb
language plpgsql immutable as $$
declare
  v_out jsonb := '[]'::jsonb;
  i int;
  e jsonb;
  v_pos jsonb;
  v_veh jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'array' then return null; end if;
  for i in 0 .. least(jsonb_array_length(p), 2) - 1 loop
    e := p -> i;
    if jsonb_typeof(e) = 'object' then
      v_pos := case when private.valid_pos(e -> 'pos') then private.clean_pos(e -> 'pos') else null end;
      v_veh := private.clean_veh(e -> 'veh');
      if v_pos is not null and v_veh is not null then
        v_out := v_out || jsonb_build_array(jsonb_build_object(
          'pos', v_pos, 'rot', private.clean_arr(e -> 'rot', 4), 'vel', private.clean_arr(e -> 'vel', 3), 'veh', v_veh));
      end if;
    end if;
  end loop;
  if jsonb_array_length(v_out) = 0 then return null; end if;
  return v_out;
end $$;

-- Remplace server_sync (0002) : ajoute p_convoy (optionnel, ignoré si l'appelant n'est pas l'hôte) et
-- renvoie is_host + convoy. Le signature change (paramètre en plus) : on retire l'ancienne version pour
-- éviter une fonction en double (PostgREST pourrait sinon hésiter entre les deux).
drop function if exists public.server_sync(text, jsonb, jsonb, jsonb, jsonb);

create or replace function public.server_sync(p_level text, p_pos jsonb, p_rot jsonb, p_vel jsonb, p_veh jsonb, p_convoy jsonb default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_srv uuid;
  v_name text; v_max int;
  v_host uuid;
  v_is_host boolean;
  v_convoy jsonb;
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
  perform private.expire_members();
  -- hôte du trafic partagé : le membre encore présent depuis le plus longtemps sur ce serveur.
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

revoke all on function public.server_sync(text, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.server_sync(text, jsonb, jsonb, jsonb, jsonb, jsonb) to authenticated;
