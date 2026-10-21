-- =====================================================================================
-- GRNFR Online - 0006 : garages physiques par serveur de jeu (une tablette par place du serveur).
-- À exécuter APRÈS 0001-0005 (Supabase > SQL Editor > Run).
--
-- Chaque serveur de jeu a autant de garages que de places (max_players, 4 par défaut) : un garage par joueur
-- qui en a besoin, jamais plus. Le garage reste au même endroit tant que son propriétaire reste sur le
-- serveur. Un joueur ne voit sa propre tablette s'ouvrir qu'à proximité de SON garage (vérifié côté Lua, voir
-- garage.lua) ; cette table se contente de dire QUI a quel garage, et OÙ (pour afficher les autres tablettes,
-- visibles mais inutilisables par qui n'en est pas propriétaire).
-- =====================================================================================

create table if not exists public.garage_spots (
  server_id  uuid not null references public.game_servers (id) on delete cascade,
  slot       int not null check (slot >= 0),
  user_id    uuid references public.profiles (id) on delete set null,
  level      text,
  pos        jsonb,
  created_at timestamptz not null default now(),
  primary key (server_id, slot)
);
create index if not exists garage_spots_user on public.garage_spots (user_id);

-- Donne mon garage sur mon serveur actuel : le mien s'il existe déjà (position jamais changée après coup),
-- sinon en crée un nouveau à la position proposée (choisie côté Lua : lieu nommé "garage" si possible, sinon
-- un point de route au hasard), en réutilisant une place laissée par quelqu'un qui n'est plus sur le serveur.
create or replace function public.claim_garage_spot(p_level text, p_pos jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_srv uuid;
  v_max int;
  v_slot int;
  v_row public.garage_spots;
  v_level text;
  v_pos jsonb;
begin
  select server_id into v_srv from public.server_members where user_id = v_me;
  if v_srv is null then raise exception 'not_in_server'; end if;
  select max_players into v_max from public.game_servers where id = v_srv;

  select * into v_row from public.garage_spots where server_id = v_srv and user_id = v_me;
  if v_row.slot is not null then
    return jsonb_build_object('slot', v_row.slot, 'level', v_row.level, 'pos', v_row.pos);
  end if;

  if not private.valid_pos(p_pos) then raise exception 'bad_position'; end if;

  -- complet : on libère une place tenue par quelqu'un qui a quitté le serveur, s'il y en a une
  if (select count(*) from public.garage_spots where server_id = v_srv) >= v_max then
    delete from public.garage_spots where ctid in (
      select g.ctid from public.garage_spots g where g.server_id = v_srv
        and not exists (select 1 from public.server_members m where m.server_id = v_srv and m.user_id = g.user_id)
      limit 1
    );
  end if;
  if (select count(*) from public.garage_spots where server_id = v_srv) >= v_max then
    raise exception 'garage_full';
  end if;

  select coalesce(min(s), 0) into v_slot from (
    select generate_series(0, v_max - 1) as s
    except
    select slot from public.garage_spots where server_id = v_srv
  ) free;

  v_level := left(coalesce(p_level, 'unknown'), 60);
  v_pos := private.clean_pos(p_pos);
  insert into public.garage_spots (server_id, slot, user_id, level, pos) values (v_srv, v_slot, v_me, v_level, v_pos);
  return jsonb_build_object('slot', v_slot, 'level', v_level, 'pos', v_pos);
end $$;

-- Tous les garages de mon serveur actuel (position + numéro de place), pour afficher les tablettes des autres
-- joueurs sans révéler leur pseudo (déjà visible par ailleurs via server_sync si on est assez proche).
create or replace function public.get_server_garage_spots() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_srv uuid;
begin
  select server_id into v_srv from public.server_members where user_id = v_me;
  if v_srv is null then raise exception 'not_in_server'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('slot', g.slot, 'pos', g.pos, 'mine', g.user_id = v_me) order by g.slot)
                     from public.garage_spots g where g.server_id = v_srv), '[]'::jsonb);
end $$;

alter table public.garage_spots enable row level security;
revoke all on public.garage_spots from anon, authenticated;
revoke all on function public.claim_garage_spot(text, jsonb), public.get_server_garage_spots() from public, anon, authenticated;
grant execute on function public.claim_garage_spot(text, jsonb), public.get_server_garage_spots() to authenticated;
