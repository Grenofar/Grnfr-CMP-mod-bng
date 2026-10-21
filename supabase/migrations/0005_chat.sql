-- =====================================================================================
-- GRNFR Online - 0005 : chat textuel entre joueurs d'un même serveur de jeu.
-- À exécuter APRÈS 0001, 0002, 0003 et 0004 (Supabase > SQL Editor > Run).
-- =====================================================================================

create table if not exists public.chat_messages (
  id         bigserial primary key,
  server_id  uuid not null references public.game_servers (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  text       text not null check (char_length(text) between 1 and 200),
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_server on public.chat_messages (server_id, created_at);

-- Le serveur visé est toujours le mien actuel (comme toutes les autres actions de serveur : pas besoin de le
-- transmettre depuis le client, impossible de parler sur un serveur où l'on n'est pas). Ménage à chaque envoi
-- (table toujours petite) : le chat n'est pas un historique permanent.
create or replace function public.send_chat_message(p_text text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_text text := trim(coalesce(p_text, '')); v_srv uuid;
begin
  select server_id into v_srv from public.server_members where user_id = v_me;
  if v_srv is null then raise exception 'not_in_server'; end if;
  if v_text = '' or char_length(v_text) > 200 then raise exception 'bad_message'; end if;
  insert into public.chat_messages (server_id, user_id, text) values (v_srv, v_me, v_text);
  delete from public.chat_messages where created_at < now() - interval '2 hours';
end $$;

create or replace function public.get_chat_messages(p_limit int default 50) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_srv uuid;
begin
  select server_id into v_srv from public.server_members where user_id = v_me;
  if v_srv is null then raise exception 'not_in_server'; end if;
  return coalesce((select jsonb_agg(x order by (x ->> 'created_at')) from (
    select jsonb_build_object('id', m.id, 'username', p.username, 'text', m.text, 'created_at', m.created_at) as x
      from public.chat_messages m join public.profiles p on p.id = m.user_id
     where m.server_id = v_srv
     order by m.created_at desc
     limit greatest(1, least(coalesce(p_limit, 50), 100))
  ) s), '[]'::jsonb);
end $$;

alter table public.chat_messages enable row level security;
revoke all on public.chat_messages from anon, authenticated;
revoke all on function public.send_chat_message(text), public.get_chat_messages(int) from public, anon, authenticated;
grant execute on function public.send_chat_message(text), public.get_chat_messages(int) to authenticated;
