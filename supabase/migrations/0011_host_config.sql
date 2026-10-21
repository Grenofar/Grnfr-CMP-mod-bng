-- =====================================================================================
-- GRNFR Online - 0011 : stockage de la configuration de GRNFR Host CMP (le serveur auto-hébergé,
-- host/) dans Supabase, à la place du fichier local. Pas de compte joueur requis : au premier
-- lancement, l'app génère un identifiant aléatoire (UUID v4, gardé dans grnfr-host.id, à côté de
-- l'exécutable) — connaître cet identifiant suffit à lire/écrire SA configuration (nom, mot de
-- passe du relais, port). Sécurité "limitée, pas infaillible" (même logique que l'anti-cheat du
-- reste du projet, voir CLAUDE.md) : un identifiant volé permet de changer la config de CE host,
-- rien d'autre (pas d'argent, pas de compte joueur, pas d'accès aux autres tables).
-- À exécuter APRÈS 0001-0010 (Supabase > SQL Editor > Run).
-- =====================================================================================

create table if not exists public.hosts (
  id         uuid primary key,
  name       text not null default 'Serveur GRNFR',
  password   text,
  port       int not null default 30814 check (port > 0 and port < 65536),
  updated_at timestamptz not null default now()
);

alter table public.hosts enable row level security;
revoke all on public.hosts from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated; -- no-op si déjà fait en 0001, gardé par cohérence

create or replace function public.host_config_get(p_host_id uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('name', name, 'password', coalesce(password, ''), 'port', port)
    from public.hosts where id = p_host_id
$$;

create or replace function public.host_config_set(p_host_id uuid, p_name text, p_password text, p_port int) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_host_id is null then raise exception 'bad_host_id'; end if;
  if p_port is null or p_port <= 0 or p_port > 65535 then raise exception 'bad_port'; end if;
  insert into public.hosts (id, name, password, port, updated_at)
  values (p_host_id, coalesce(nullif(trim(p_name), ''), 'Serveur GRNFR'), nullif(p_password, ''), p_port, now())
  on conflict (id) do update set name = excluded.name, password = excluded.password, port = excluded.port, updated_at = now();
end $$;

revoke all on function public.host_config_get(uuid), public.host_config_set(uuid, text, text, int) from public, authenticated;
grant execute on function public.host_config_get(uuid), public.host_config_set(uuid, text, text, int) to anon;
