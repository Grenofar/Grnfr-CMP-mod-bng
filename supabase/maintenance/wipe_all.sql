-- =====================================================================================
-- GRNFR Online - RESET COMPLET (⚠️ IRRÉVERSIBLE, supprime TOUTES les données) ⚠️
--
-- Ce n'est PAS une migration numérotée : ne la mettez jamais dans supabase/migrations/.
-- Vide toutes les tables (joueurs, argent, véhicules, serveurs, chat, catalogue, config, releases,
-- hosts) ET tous les comptes (auth.users, ce qui supprime les profils en cascade). Le SCHÉMA
-- (tables, fonctions, droits) n'est pas touché.
--
-- POUR TOUT REMETTRE : relancez simplement supabase/migrations/0001 à 0011 dans l'ordre (les mêmes
-- fichiers que d'habitude). Toutes leurs données de départ (catalogue, réglages par défaut...)
-- s'insèrent avec "on conflict do nothing" / "where not exists" : comme les tables sont vides après
-- ce wipe, elles se repeuplent entièrement, sans rien à copier-coller à part ces 11 fichiers.
--
-- À utiliser seulement si vous voulez repartir de zéro (tester, ou remettre un serveur propre).
-- Ne corrige PAS un problème de connexion réseau entre le jeu et Supabase (si "connexion au
-- serveur impossible" apparaît, ce script ne changera rien : c'est le jeu qui n'arrive pas à
-- joindre Supabase, pas une histoire de données).
-- =====================================================================================

truncate table
  public.chat_messages,
  public.drag_entries,
  public.drag_races,
  public.garage_spots,
  public.garage_vehicles,
  public.hosts,
  public.jobs,
  public.listings,
  public.mod_releases,
  public.server_config,
  public.server_members,
  public.taxi_requests,
  public.trades,
  public.transactions,
  public.dealership_catalog,
  public.game_servers,
  public.profiles
restart identity cascade;

delete from auth.users;
