-- =====================================================================================
-- GRNFR Online - RESET TOTAL DE LA STRUCTURE (⚠️ IRRÉVERSIBLE, pas juste les données) ⚠️
--
-- Supprime ENTIÈREMENT les schémas "public" et "private" (toutes les tables, fonctions,
-- triggers, vues, droits... tout) et les recrée vides. Vide aussi tous les comptes
-- (auth.users). Après ce script, la base est comme un projet Supabase tout neuf pour cette
-- appli : RIEN ne marche (mod, site, host) tant que vous n'avez pas relancé TOUTES les
-- migrations, dans l'ordre, une par une : 0001 → 0002 → 0003 → 0004 → 0005 → 0006 → 0007 →
-- 0008 → 0009 → 0010 → 0011 (supabase/migrations/). Ne sautez aucun numéro.
--
-- Ne touche PAS aux schémas gérés par Supabase lui-même (auth, storage) à part vider les
-- comptes (auth.users) — on ne supprime jamais ces schémas-là, trop risqué pour la plateforme
-- (ça casserait l'authentification de tout le projet, pas juste cette appli). Les fichiers déjà
-- envoyés dans Storage (zips du mod, bucket "releases") ne sont pas touchés par ce script.
-- =====================================================================================

drop schema if exists private cascade;
drop schema if exists public cascade;
create schema public;
grant usage on schema public to anon, authenticated, service_role;

delete from auth.users;
