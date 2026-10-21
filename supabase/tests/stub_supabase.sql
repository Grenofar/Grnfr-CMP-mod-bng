-- Imite le strict minimum de Supabase (rôles, auth.users, auth.uid) pour tester le schéma sur un Postgres nu.
do $$ begin if not exists (select from pg_roles where rolname = 'anon') then create role anon nologin; create role authenticated nologin; create role service_role nologin; end if; end $$;
create schema auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text, raw_user_meta_data jsonb not null default '{}');
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth, public to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
alter default privileges in schema public grant execute on functions to anon, authenticated;
