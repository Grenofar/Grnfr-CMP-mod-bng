-- =====================================================================================
-- GRNFR Online - 0004 : releases du mod, distribuées depuis Supabase Storage.
-- À exécuter APRÈS 0001, 0002 et 0003 (Supabase > SQL Editor > Run).
--
-- Le bucket Storage "releases" est public (le zip doit être téléchargeable sans compte).
-- La table mod_releases n'est accessible en écriture par AUCUN rôle client (RLS, aucun droit accordé) :
-- seul scripts/release.mjs, avec la clé service_role (jamais dans le mod ni sur le site), y écrit en
-- contournant RLS. Les joueurs et le site lisent uniquement via get_latest_release() / get_releases().
-- =====================================================================================

-- Bucket public (ignoré si le schéma storage n'existe pas, ex. tests locaux sur un faux Supabase).
do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public) values ('releases', 'releases', true)
    on conflict (id) do update set public = true;
  end if;
end $$;

create table if not exists public.mod_releases (
  id          uuid primary key default gen_random_uuid(),
  version     text not null unique check (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  notes       text,
  file_path   text not null check (file_path ~ '^[A-Za-z0-9_.-]+$'),
  size        bigint not null check (size > 0),
  sha256      text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  created_at  timestamptz not null default now(),
  is_latest   boolean not null default false
);
create index if not exists mod_releases_latest on public.mod_releases (is_latest) where is_latest;

-- La dernière release insérée devient "is_latest" ; toutes les autres repassent à false. Permet aussi un
-- retour en arrière manuel (admin Supabase) en remettant is_latest à true sur une ancienne ligne.
create or replace function private.mark_latest_release() returns trigger
language plpgsql as $$
begin
  update public.mod_releases set is_latest = false where id <> new.id and is_latest;
  new.is_latest := true;
  return new;
end $$;
drop trigger if exists mod_releases_latest_trg on public.mod_releases;
create trigger mod_releases_latest_trg before insert on public.mod_releases
  for each row execute function private.mark_latest_release();

create or replace function public.get_latest_release() returns jsonb
language sql security definer set search_path = public, pg_temp as $$
  select coalesce((
    select jsonb_build_object('version', r.version, 'notes', r.notes, 'file_path', r.file_path,
                               'size', r.size, 'sha256', r.sha256, 'created_at', r.created_at)
      from public.mod_releases r where r.is_latest limit 1
  ), 'null'::jsonb) $$;

create or replace function public.get_releases(p_limit int default 10) returns jsonb
language sql security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('version', r.version, 'notes', r.notes, 'file_path', r.file_path,
                                                'size', r.size, 'sha256', r.sha256, 'created_at', r.created_at,
                                                'is_latest', r.is_latest) order by r.created_at desc), '[]'::jsonb)
    from (select * from public.mod_releases order by created_at desc
           limit greatest(1, least(coalesce(p_limit, 10), 50))) r $$;

alter table public.mod_releases enable row level security;
revoke all on public.mod_releases from anon, authenticated;
revoke all on function public.get_latest_release(), public.get_releases(int) from public, anon, authenticated;
grant execute on function public.get_latest_release(), public.get_releases(int) to anon, authenticated;
