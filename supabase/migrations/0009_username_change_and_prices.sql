-- =====================================================================================
-- GRNFR Online - 0009 : changement de pseudo après création + prix du catalogue alignés
-- sur les valeurs par défaut du jeu de base (champ "Value" de la configuration par défaut
-- de chaque véhicule, lues directement dans les fichiers du jeu).
-- À exécuter APRÈS 0001-0008 (Supabase > SQL Editor > Run).
-- =====================================================================================

-- ------------------------------------------------------------------ changer de pseudo
-- set_username (0002) ne peut être utilisé qu'une fois (profil pas encore confirmé). change_username
-- permet de le refaire ensuite, avec un délai anti-abus (1 changement / 24h) pour limiter l'usurpation
-- répétée d'un pseudo tout juste libéré par quelqu'un d'autre.
alter table public.profiles add column if not exists username_changed_at timestamptz;

create or replace function public.change_username(p_username text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_last timestamptz;
begin
  if p_username !~ '^[A-Za-z0-9_]{3,20}$' then raise exception 'username_invalid'; end if;
  if exists (select 1 from public.profiles where lower(username) = lower(p_username) and id <> v_me) then raise exception 'username_taken'; end if;
  select username_changed_at into v_last from public.profiles where id = v_me;
  if v_last is not null and v_last > now() - interval '24 hours' then raise exception 'username_change_cooldown'; end if;
  begin
    update public.profiles set username = p_username, username_confirmed = true, username_changed_at = now() where id = v_me;
  exception when unique_violation then raise exception 'username_taken';
  end;
end $$;

revoke all on function public.change_username(text) from public, anon, authenticated;
grant execute on function public.change_username(text) to authenticated;

-- ------------------------------------------------------------------ prix du catalogue = valeurs de base du jeu
-- Les prix insérés en 0001 étaient approximatifs. Voici le champ "Value" réel de la configuration par défaut
-- ("default_pc" dans vehicles/<model>/info.json) de chaque véhicule, lu dans les fichiers du jeu (BeamNG.drive) :
update public.dealership_catalog set price = 19000  where model_key = 'covet';
update public.dealership_catalog set price = 27700  where model_key = 'pessima';
update public.dealership_catalog set price = 60300  where model_key = 'sunburst2';
update public.dealership_catalog set price = 74400  where model_key = 'vivace';
update public.dealership_catalog set price = 24500  where model_key = 'miramar';
update public.dealership_catalog set price = 44500  where model_key = 'pickup';
update public.dealership_catalog set price = 43000  where model_key = 'etk800';
update public.dealership_catalog set price = 34500  where model_key = 'bastion';
update public.dealership_catalog set price = 45000  where model_key = 'barstow';
update public.dealership_catalog set price = 48000  where model_key = 'moonhawk';
update public.dealership_catalog set price = 180000 where model_key = 'bolide';
update public.dealership_catalog set price = 205000 where model_key = 'scintilla';
update public.dealership_catalog set price = 43000  where model_key = 'fullsize';
update public.dealership_catalog set price = 450000 where model_key = 'citybus';
