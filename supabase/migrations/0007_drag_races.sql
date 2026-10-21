-- =====================================================================================
-- GRNFR Online - 0007 : courses de drag organisées entre joueurs d'un même serveur, avec mise d'argent.
-- À exécuter APRÈS 0001-0006 (Supabase > SQL Editor > Run).
--
-- Une seule course active par serveur à la fois. Déroulement : un joueur propose une course (point de départ
-- + point d'arrivée) -> phase de mises (chacun choisit un montant et le mise, débité immédiatement en garantie)
-- -> l'hôte lance (minimum 2 joueurs) -> chaque joueur signale son temps d'arrivée -> dès que tous ont un temps
-- (ou que l'hôte force la fin), le plus rapide empoche tout le pot. Le départ (anti faux départ, launch
-- control) et la détection de la ligne d'arrivée sont gérés côté jeu (voir drag.lua) : la base ne fait que
-- valider que le temps annoncé n'est pas physiquement impossible (comme le taxi : limite, n'empêche pas tout).
-- =====================================================================================

insert into public.server_config (key, value, description) values
  ('drag_min_distance_m', '100',   'Longueur minimum d''une course de drag (m)'),
  ('drag_max_distance_m', '3000',  'Longueur maximum d''une course de drag (m)'),
  ('drag_max_speed_mps',  '100',   'Vitesse moyenne max crédible pour valider un temps de drag (m/s)'),
  ('drag_min_stake',      '100',   'Mise minimum pour une course de drag'),
  ('drag_max_stake',      '50000', 'Mise maximum pour une course de drag')
on conflict (key) do nothing;

create table if not exists public.drag_races (
  id          uuid primary key default gen_random_uuid(),
  server_id   uuid not null references public.game_servers (id) on delete cascade,
  host_id     uuid not null references public.profiles (id),
  status      text not null default 'betting' check (status in ('betting', 'running', 'finished', 'cancelled')),
  level       text,
  start_pos   jsonb,
  finish_pos  jsonb,
  pot         bigint not null default 0 check (pot >= 0),
  winner_id   uuid references public.profiles (id),
  created_at  timestamptz not null default now(),
  started_at  timestamptz,
  finished_at timestamptz
);
-- une seule course "vivante" (pas encore terminée/annulée) par serveur
create unique index if not exists drag_one_active_per_server on public.drag_races (server_id)
  where status in ('betting', 'running');

create table if not exists public.drag_entries (
  race_id      uuid not null references public.drag_races (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  stake        bigint not null check (stake > 0),
  finish_ms    int,
  disqualified boolean not null default false,
  joined_at    timestamptz not null default now(),
  primary key (race_id, user_id)
);

-- Désigne le vainqueur (temps valide le plus bas) et paie le pot ; si personne n'a de temps valide, chacun
-- récupère sa mise. Fonction interne (appelée par report_drag_finish / force_finish_drag_race).
create or replace function private.finish_drag_race(p_race uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.drag_races; v_winner uuid; v_pot bigint; e record;
begin
  select * into r from public.drag_races where id = p_race for update;
  if r.id is null or r.status <> 'running' then return; end if;
  select user_id into v_winner from public.drag_entries
   where race_id = p_race and finish_ms is not null and not disqualified
   order by finish_ms asc limit 1;
  v_pot := r.pot;
  if v_winner is not null then
    perform private.add_money(v_winner, v_pot, 'drag_win', null, 'Victoire course de drag');
  else
    for e in select * from public.drag_entries where race_id = p_race loop
      perform private.add_money(e.user_id, e.stake, 'drag_refund', null, 'Course de drag sans vainqueur');
    end loop;
    v_pot := 0;
  end if;
  update public.drag_races set status = 'finished', winner_id = v_winner, pot = v_pot, finished_at = now() where id = p_race;
end $$;

create or replace function public.propose_drag_race(p_level text, p_start jsonb, p_finish jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_srv uuid; v_dist float8; v_id uuid;
begin
  select server_id into v_srv from public.server_members where user_id = v_me;
  if v_srv is null then raise exception 'not_in_server'; end if;
  if not private.valid_pos(p_start) or not private.valid_pos(p_finish) then raise exception 'bad_position'; end if;
  if exists (select 1 from public.drag_races where server_id = v_srv and status in ('betting', 'running')) then
    raise exception 'race_active';
  end if;
  v_dist := private.dist(p_start, p_finish);
  if v_dist < private.cfg('drag_min_distance_m') then raise exception 'too_short'; end if;
  if v_dist > private.cfg('drag_max_distance_m') then raise exception 'too_long'; end if;
  insert into public.drag_races (server_id, host_id, level, start_pos, finish_pos)
  values (v_srv, v_me, left(coalesce(p_level, 'unknown'), 60), private.clean_pos(p_start), private.clean_pos(p_finish))
  returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;

-- Rejoindre = miser : la mise est débitée immédiatement (garantie), remboursée si on se désiste ou si la
-- course est annulée avant le départ.
create or replace function public.join_drag_race(p_race uuid, p_stake bigint) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_srv uuid; r public.drag_races;
begin
  select server_id into v_srv from public.server_members where user_id = v_me;
  if v_srv is null then raise exception 'not_in_server'; end if;
  select * into r from public.drag_races where id = p_race for update;
  if r.id is null or r.server_id <> v_srv then raise exception 'race_not_found'; end if;
  if r.status <> 'betting' then raise exception 'betting_closed'; end if;
  if exists (select 1 from public.drag_entries where race_id = p_race and user_id = v_me) then raise exception 'already_in'; end if;
  if p_stake is null or p_stake < private.cfg('drag_min_stake') or p_stake > private.cfg('drag_max_stake') then
    raise exception 'bad_stake';
  end if;
  perform private.add_money(v_me, -p_stake, 'drag_stake', null, 'Mise course de drag');
  insert into public.drag_entries (race_id, user_id, stake) values (p_race, v_me, p_stake);
  update public.drag_races set pot = pot + p_stake where id = p_race;
  return jsonb_build_object('ok', true);
end $$;

-- Se désister (remboursé) pendant les mises. Si c'est l'hôte qui part, la course est annulée et tout le
-- monde est remboursé (personne d'autre ne peut la lancer).
create or replace function public.leave_drag_race(p_race uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); r public.drag_races; e public.drag_entries; x record;
begin
  select * into r from public.drag_races where id = p_race for update;
  if r.id is null or r.status <> 'betting' then raise exception 'betting_closed'; end if;
  select * into e from public.drag_entries where race_id = p_race and user_id = v_me;
  if e.user_id is not null then
    perform private.add_money(v_me, e.stake, 'drag_refund', null, 'Désistement avant le départ');
    delete from public.drag_entries where race_id = p_race and user_id = v_me;
    update public.drag_races set pot = pot - e.stake where id = p_race;
  end if;
  if r.host_id = v_me then
    for x in select * from public.drag_entries where race_id = p_race loop
      perform private.add_money(x.user_id, x.stake, 'drag_refund', null, 'Course de drag annulée (hôte parti)');
    end loop;
    delete from public.drag_entries where race_id = p_race;
    update public.drag_races set status = 'cancelled', pot = 0 where id = p_race;
  end if;
end $$;

create or replace function public.start_drag_race(p_race uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); r public.drag_races; v_n int;
begin
  select * into r from public.drag_races where id = p_race for update;
  if r.id is null then raise exception 'race_not_found'; end if;
  if r.host_id <> v_me then raise exception 'forbidden'; end if;
  if r.status <> 'betting' then raise exception 'betting_closed'; end if;
  select count(*) into v_n from public.drag_entries where race_id = p_race;
  if v_n < 2 then raise exception 'not_enough_players'; end if;
  update public.drag_races set status = 'running', started_at = now() where id = p_race;
  return jsonb_build_object('ok', true);
end $$;

-- p_ms = temps écoulé (ms) entre le TOP et la ligne d'arrivée, mesuré par le jeu. Refusé si plus rapide que
-- la vitesse moyenne maximum crédible (anti-triche limité, comme le taxi : voir drag_max_speed_mps).
create or replace function public.report_drag_finish(p_race uuid, p_ms int) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); r public.drag_races; v_min_ms int; v_remaining int;
begin
  select * into r from public.drag_races where id = p_race for update;
  if r.id is null or r.status <> 'running' then raise exception 'race_not_running'; end if;
  if not exists (select 1 from public.drag_entries where race_id = p_race and user_id = v_me) then raise exception 'not_entered'; end if;
  if exists (select 1 from public.drag_entries where race_id = p_race and user_id = v_me and finish_ms is not null) then
    raise exception 'already_finished';
  end if;
  if p_ms is null or p_ms <= 0 then raise exception 'bad_time'; end if;
  v_min_ms := ceil(private.dist(r.start_pos, r.finish_pos) / private.cfg('drag_max_speed_mps') * 1000);
  if p_ms < v_min_ms then raise exception 'too_fast'; end if;
  update public.drag_entries set finish_ms = p_ms where race_id = p_race and user_id = v_me;
  select count(*) into v_remaining from public.drag_entries where race_id = p_race and finish_ms is null and not disqualified;
  if v_remaining = 0 then perform private.finish_drag_race(p_race); end if;
  return jsonb_build_object('ok', true);
end $$;

-- L'hôte force la fin (ex. un joueur a quitté la partie sans signaler son temps) : les retardataires sont
-- disqualifiés (leur mise reste dans le pot) et le plus rapide des temps déjà reçus empoche tout.
create or replace function public.force_finish_drag_race(p_race uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); r public.drag_races;
begin
  select * into r from public.drag_races where id = p_race for update;
  if r.id is null then raise exception 'race_not_found'; end if;
  if r.host_id <> v_me then raise exception 'forbidden'; end if;
  if r.status <> 'running' then raise exception 'race_not_running'; end if;
  update public.drag_entries set disqualified = true where race_id = p_race and finish_ms is null;
  perform private.finish_drag_race(p_race);
  return jsonb_build_object('ok', true);
end $$;

-- Course en cours (ou terminée depuis moins de 2 minutes, pour afficher le résumé) sur MON serveur actuel.
create or replace function public.get_drag_race() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_srv uuid; r public.drag_races;
begin
  select server_id into v_srv from public.server_members where user_id = v_me;
  if v_srv is null then raise exception 'not_in_server'; end if;
  select * into r from public.drag_races
   where server_id = v_srv
     and (status in ('betting', 'running') or (status = 'finished' and finished_at > now() - interval '2 minutes'))
   order by created_at desc limit 1;
  if r.id is null then return 'null'::jsonb; end if;
  return jsonb_build_object(
    'id', r.id, 'status', r.status, 'host', (select username from public.profiles where id = r.host_id),
    'is_host', r.host_id = v_me, 'pot', r.pot, 'level', r.level, 'start_pos', r.start_pos, 'finish_pos', r.finish_pos,
    'winner', (select username from public.profiles where id = r.winner_id),
    'entries', coalesce((select jsonb_agg(jsonb_build_object('username', p.username, 'stake', de.stake,
                   'finish_ms', de.finish_ms, 'disqualified', de.disqualified, 'mine', de.user_id = v_me) order by de.joined_at)
                 from public.drag_entries de join public.profiles p on p.id = de.user_id
                where de.race_id = r.id), '[]'::jsonb)
  );
end $$;

alter table public.drag_races enable row level security;
alter table public.drag_entries enable row level security;
revoke all on public.drag_races, public.drag_entries from anon, authenticated;
revoke all on function
  public.propose_drag_race(text, jsonb, jsonb), public.join_drag_race(uuid, bigint), public.leave_drag_race(uuid),
  public.start_drag_race(uuid), public.report_drag_finish(uuid, int), public.force_finish_drag_race(uuid), public.get_drag_race()
  from public, anon, authenticated;
grant execute on function
  public.propose_drag_race(text, jsonb, jsonb), public.join_drag_race(uuid, bigint), public.leave_drag_race(uuid),
  public.start_drag_race(uuid), public.report_drag_finish(uuid, int), public.force_finish_drag_race(uuid), public.get_drag_race()
  to authenticated;
