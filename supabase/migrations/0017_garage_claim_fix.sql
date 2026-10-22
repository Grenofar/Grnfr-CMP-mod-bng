-- =====================================================================================
-- GRNFR Online - 0017 : corrige une course sur claim_garage_spot (plusieurs joueurs qui rejoignent au même
-- moment pouvaient recevoir le MÊME garage). + get_server_garage_spots renvoie maintenant le pseudo du
-- propriétaire (pour l'affichage "Garage de <pseudo>" / "Garage non pris" dans garage.lua).
-- À exécuter APRÈS 0001-0016.
--
-- Avant : le Lua calculait LUI-MÊME le garage réel le plus proche et libre (d'après un cache local des garages
-- déjà pris, rafraîchi toutes les 5 s), puis demandait au serveur de l'enregistrer à CETTE position. Deux
-- joueurs qui rejoignent presque en même temps (ce qui arrive : un nouveau joueur apparaît tout près d'un
-- joueur déjà présent, voir travel.lua) voyaient tous les deux le même garage comme "libre" avant que l'un des
-- deux ait eu le temps d'enregistrer sa place côté serveur -> même garage pour les deux.
-- Après : le Lua envoie la liste ENTIÈRE des vrais garages de la carte, triée par distance (p_candidates) ; le
-- serveur verrouille (for update) tous les garages de CE serveur et choisit LUI-MÊME le premier candidat non
-- déjà pris par un membre toujours présent -> plus de course possible, un seul claim_garage_spot à la fois par
-- serveur peut s'exécuter.
-- =====================================================================================

create or replace function public.claim_garage_spot(p_level text, p_candidates jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_srv uuid;
  v_max int;
  v_slot int;
  v_row public.garage_spots;
  v_level text;
  v_pos jsonb;
  c jsonb;
  v_taken constant numeric := 25; -- m : même seuil que garage.lua (TAKEN)
begin
  select server_id into v_srv from public.server_members where user_id = v_me;
  if v_srv is null then raise exception 'not_in_server'; end if;
  select max_players into v_max from public.game_servers where id = v_srv;

  -- Verrouille tous les garages de ce serveur : un seul joueur à la fois choisit son garage sur ce serveur.
  perform 1 from public.garage_spots where server_id = v_srv for update;

  select * into v_row from public.garage_spots where server_id = v_srv and user_id = v_me;
  if v_row.slot is not null then
    return jsonb_build_object('slot', v_row.slot, 'level', v_row.level, 'pos', v_row.pos);
  end if;

  if jsonb_typeof(p_candidates) is distinct from 'array' or jsonb_array_length(p_candidates) = 0 then
    raise exception 'bad_position';
  end if;

  -- complet : on libère une place tenue par quelqu'un qui a quitté le serveur, s'il y en a une
  if (select count(*) from public.garage_spots where server_id = v_srv) >= v_max then
    delete from public.garage_spots where ctid in (
      select g.ctid from public.garage_spots g where g.server_id = v_srv
        and not exists (select 1 from public.server_members m where m.server_id = v_srv and m.user_id = g.user_id)
      limit 1
    );
  end if;
  if (select count(*) from public.garage_spots where server_id = v_srv) >= v_max then raise exception 'garage_full'; end if;

  -- premier candidat (déjà trié par distance côté Lua) qui n'est pas déjà pris par un membre toujours présent
  for c in select * from jsonb_array_elements(p_candidates) loop
    if private.valid_pos(c) and not exists (
      select 1 from public.garage_spots g
       where g.server_id = v_srv and g.pos is not null and private.dist(g.pos, c) < v_taken
         and exists (select 1 from public.server_members m where m.server_id = v_srv and m.user_id = g.user_id)
    ) then
      v_pos := c; exit;
    end if;
  end loop;
  if v_pos is null then raise exception 'garage_full'; end if;

  select coalesce(min(s), 0) into v_slot from (
    select generate_series(0, v_max - 1) as s
    except
    select slot from public.garage_spots where server_id = v_srv
  ) free;

  v_level := left(coalesce(p_level, 'unknown'), 60);
  v_pos := private.clean_pos(v_pos);
  insert into public.garage_spots (server_id, slot, user_id, level, pos) values (v_srv, v_slot, v_me, v_level, v_pos);
  return jsonb_build_object('slot', v_slot, 'level', v_level, 'pos', v_pos);
end $$;

-- + pseudo du propriétaire (déjà visible par ailleurs via server_sync, ce n'est pas une donnée privée).
create or replace function public.get_server_garage_spots() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_srv uuid;
begin
  select server_id into v_srv from public.server_members where user_id = v_me;
  if v_srv is null then raise exception 'not_in_server'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('slot', g.slot, 'pos', g.pos, 'mine', g.user_id = v_me,
                     'username', p.username) order by g.slot)
                     from public.garage_spots g left join public.profiles p on p.id = g.user_id
                    where g.server_id = v_srv), '[]'::jsonb);
end $$;

revoke all on function public.claim_garage_spot(text, jsonb), public.get_server_garage_spots() from public, anon, authenticated;
grant execute on function public.claim_garage_spot(text, jsonb), public.get_server_garage_spots() to authenticated;
