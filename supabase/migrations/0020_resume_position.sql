-- =====================================================================================
-- GRNFR Online - 0020 : reprise à la dernière position connue en se reconnectant à un serveur où l'on est déjà
-- membre, au lieu d'être systématiquement renvoyé au garage / près d'un autre joueur (TODO point 3bis, partie
-- "sauvegarde périodique" de CLAUDE.md — la position est déjà sauvegardée en continu par heartbeat() toutes les
-- ~5 s, rien à faire côté sauvegarde elle-même ; ce qui manquait, c'est l'UTILISER à la reconnexion).
-- Annule aussi les missions en cours (taxi PNJ/bus/taxi IA, livraison, course de drag en mise) à ce moment-là,
-- en réutilisant les fonctions d'annulation déjà existantes et testées — jamais de nouvelle logique d'argent.
-- Les dégâts persistants (même TODO point, autre partie) restent À FAIRE : liés à la phase 3 (réparation), pas
-- traités ici, voir CLAUDE.md.
-- À exécuter APRÈS 0001-0019.
-- =====================================================================================

create or replace function public.join_server(p_server uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_srv public.game_servers;
  v_prof public.profiles;
  v_n int;
  v_resumed boolean := false;
  r record;
begin
  select * into v_prof from public.profiles where id = v_me;
  if v_prof.id is null or v_prof.username !~ '^[A-Za-z0-9_]{3,20}$' or not v_prof.username_confirmed then
    raise exception 'username_required';
  end if;
  select * into v_srv from public.game_servers where id = p_server for update;  -- sérialise les arrivées
  if v_srv.id is null then raise exception 'server_not_found'; end if;
  perform private.expire_stale();
  if exists (select 1 from public.server_members where user_id = v_me and server_id = v_srv.id) then
    update public.server_members set last_seen = now() where user_id = v_me;      -- déjà dedans : reconnexion
    v_resumed := true;
    -- Annule les missions en cours plutôt que de laisser le joueur revenir dans un état bloqué : on réutilise
    -- les fonctions d'annulation déjà existantes (mêmes remboursements, jamais de nouvelle logique d'argent).
    for r in select id from public.jobs where user_id = v_me and kind in ('npc_taxi', 'bus_leg', 'bot_taxi')
              and status in ('started', 'boarded') loop
      begin perform public.cancel_job(r.id); exception when others then null; end;
    end loop;
    for r in select id from public.deliveries where accepted_by = v_me and status = 'accepted' loop
      begin perform public.cancel_delivery(r.id); exception when others then null; end;
    end loop;
    for r in select de.race_id from public.drag_entries de join public.drag_races dr on dr.id = de.race_id
              where de.user_id = v_me and dr.status = 'betting' loop
      begin perform public.leave_drag_race(r.race_id); exception when others then null; end;
    end loop;
    -- chauffeur d'une course d'un autre joueur : on relâche la demande (pas d'argent escroqué avant taxi_complete,
    -- donc rien à rembourser), elle redevient disponible pour quelqu'un d'autre ou expire normalement.
    update public.taxi_requests set driver_id = null, status = 'requested', accepted_at = null, picked_up_at = null
     where driver_id = v_me and status in ('accepted', 'picked_up');
  else
    select count(*) into v_n from public.server_members where server_id = v_srv.id;
    if v_n >= v_srv.max_players then raise exception 'server_full'; end if;
    delete from public.server_members where user_id = v_me;                         -- quitte l'ancien serveur
    insert into public.server_members (user_id, server_id) values (v_me, v_srv.id);
  end if;
  return jsonb_build_object('id', v_srv.id, 'name', v_srv.name, 'max_players', v_srv.max_players,
    'resumed', v_resumed, 'level', case when v_resumed then v_prof.level else null end,
    'pos', case when v_resumed then v_prof.pos else null end);
end $$;

revoke all on function public.join_server(uuid) from public, anon, authenticated;
grant execute on function public.join_server(uuid) to authenticated;
