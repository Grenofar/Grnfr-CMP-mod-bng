-- =====================================================================================
-- GRNFR Online - 0012 : plusieurs serveurs GRNFR Host CMP par installation (host_id), tous
-- lançables en même temps depuis la même app. Remplace le modèle "une config par host_id" de
-- 0011 par une liste : chaque serveur a son propre id, nom, mot de passe, port.
-- À exécuter APRÈS 0001-0011 (Supabase > SQL Editor > Run).
-- =====================================================================================

create table if not exists public.host_servers (
  id         uuid primary key default gen_random_uuid(),
  host_id    uuid not null,
  name       text not null default 'Serveur GRNFR',
  password   text,
  port       int not null check (port > 0 and port < 65536),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists host_servers_host_id on public.host_servers (host_id);

alter table public.host_servers enable row level security;
revoke all on public.host_servers from anon, authenticated;

-- Reprend l'unique config de 0011 (si elle existe) comme premier serveur de son host_id, pour ne pas perdre
-- la configuration déjà enregistrée par un host déjà en service.
insert into public.host_servers (host_id, name, password, port, updated_at)
select id, name, password, port, updated_at from public.hosts
where not exists (select 1 from public.host_servers hs where hs.host_id = public.hosts.id);

create or replace function public.host_servers_list(p_host_id uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'name', name, 'password', coalesce(password, ''), 'port', port
         ) order by created_at), '[]'::jsonb)
    from public.host_servers where host_id = p_host_id
$$;

-- p_id null = crée un nouveau serveur ; p_id renseigné = modifie un serveur existant de CE host_id.
create or replace function public.host_server_upsert(p_host_id uuid, p_id uuid, p_name text, p_password text, p_port int) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid;
begin
  if p_host_id is null then raise exception 'bad_host_id'; end if;
  if p_port is null or p_port <= 0 or p_port > 65535 then raise exception 'bad_port'; end if;
  if p_id is null then
    insert into public.host_servers (host_id, name, password, port)
    values (p_host_id, coalesce(nullif(trim(p_name), ''), 'Serveur GRNFR'), nullif(p_password, ''), p_port)
    returning id into v_id;
  else
    update public.host_servers
       set name = coalesce(nullif(trim(p_name), ''), 'Serveur GRNFR'), password = nullif(p_password, ''), port = p_port, updated_at = now()
     where id = p_id and host_id = p_host_id
    returning id into v_id;
    if v_id is null then raise exception 'not_found'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.host_server_delete(p_host_id uuid, p_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from public.host_servers where id = p_id and host_id = p_host_id;
end $$;

revoke all on function public.host_servers_list(uuid), public.host_server_upsert(uuid, uuid, text, text, int), public.host_server_delete(uuid, uuid)
  from public, authenticated;
grant execute on function public.host_servers_list(uuid), public.host_server_upsert(uuid, uuid, text, text, int), public.host_server_delete(uuid, uuid)
  to anon;
