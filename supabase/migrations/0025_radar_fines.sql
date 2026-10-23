-- =====================================================================================
-- GRNFR Online - 0025 : radars de vitesse + amendes aux feux rouges (grand chantier Phase I, 22-23/10/2026).
-- Demande précisée par l'utilisateur : "le radar n'est pas dans la voiture" (pas un contrôle permanent partout)
-- — "mets-en pas partout" — "quand il passe à proximité il en tire la vitesse et c'est une amende ou pas".
-- Implémenté avec les VRAIS radars/caméras de feu rouge du jeu (découverts en lisant les sources :
-- lua/ge/extensions/gameplay/speedTraps.lua) : de vrais déclencheurs (BeamNGTrigger avec speedTrapType =
-- "speed" ou "redLight") placés par le jeu à des endroits précis de certaines cartes, PAS partout — le jeu
-- lui-même calcule déjà si on roulait trop vite ou si le feu était rouge (core_trafficSignals) et déclenche un
-- hook (onSpeedTrapTriggered / onRedLightCamTriggered) seulement dans ce cas. Notre mod écoute ces hooks
-- (grnfr/radar.lua) et demande une amende au serveur, qui DÉCIDE SEUL du montant (jamais le client) — la
-- vitesse/limite rapportées par le client ne servent qu'à l'affichage et sont plafonnées par sécurité (même
-- esprit "limité, pas infaillible" que le reste de l'anti-triche du projet : un client malveillant pourrait
-- simplement ne jamais appeler ces fonctions, ce qui n'est pas corrigé ici — l'amende est un mécanisme de jeu de
-- rôle, pas une mesure de sécurité dure).
-- À exécuter APRÈS 0001-0024.
-- =====================================================================================

alter table public.profiles add column if not exists last_fine_at timestamptz;

insert into public.server_config (key, value, description) values
  ('radar_fine_base',          '50',  'Radar : amende de base pour excès de vitesse'),
  ('radar_fine_per_kmh_over',  '5',   'Radar : amende supplémentaire par km/h au-dessus de la limite'),
  ('radar_max_speed_kmh',      '300', 'Radar : vitesse maximum plausible acceptée du client (sécurité)'),
  ('redlight_fine',            '150', 'Feu rouge : amende fixe'),
  ('fine_cooldown_seconds',    '20',  'Radars/feux rouges : délai minimum entre deux amendes pour un même joueur')
on conflict (key) do nothing;

-- Renvoie le montant réellement prélevé (0 si rien, par exemple pendant le délai anti-spam ou si le joueur est
-- déjà sans argent). v_me verrouillé pour éviter deux amendes simultanées de contourner le cooldown.
create or replace function public.report_speeding(p_speed_kmh numeric, p_limit_kmh numeric) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := private.require_user();
  v_last timestamptz;
  v_bal bigint;
  v_speed numeric;
  v_limit numeric;
  v_fine bigint;
begin
  select last_fine_at, balance into v_last, v_bal from public.profiles where id = v_me for update;
  if v_last is not null and now() - v_last < make_interval(secs => private.cfg('fine_cooldown_seconds')) then
    return jsonb_build_object('fine', 0, 'reason', 'cooldown');
  end if;
  v_speed := greatest(0, least(coalesce(p_speed_kmh, 0), private.cfg('radar_max_speed_kmh')));
  v_limit := greatest(0, least(coalesce(p_limit_kmh, 0), private.cfg('radar_max_speed_kmh')));
  if v_speed <= v_limit then return jsonb_build_object('fine', 0, 'reason', 'under_limit'); end if;
  v_fine := round(private.cfg('radar_fine_base') + private.cfg('radar_fine_per_kmh_over') * (v_speed - v_limit));
  v_fine := least(v_fine, v_bal);
  update public.profiles set last_fine_at = now() where id = v_me;
  if v_fine > 0 then perform private.add_money(v_me, -v_fine, 'radar_fine', null,
    'Radar : ' || round(v_speed) || ' km/h (limite ' || round(v_limit) || ')'); end if;
  return jsonb_build_object('fine', v_fine, 'speed_kmh', round(v_speed), 'limit_kmh', round(v_limit));
end $$;

create or replace function public.report_red_light() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := private.require_user(); v_last timestamptz; v_bal bigint; v_fine bigint;
begin
  select last_fine_at, balance into v_last, v_bal from public.profiles where id = v_me for update;
  if v_last is not null and now() - v_last < make_interval(secs => private.cfg('fine_cooldown_seconds')) then
    return jsonb_build_object('fine', 0, 'reason', 'cooldown');
  end if;
  v_fine := least(private.cfg('redlight_fine')::bigint, v_bal);
  update public.profiles set last_fine_at = now() where id = v_me;
  if v_fine > 0 then perform private.add_money(v_me, -v_fine, 'redlight_fine', null, 'Feu rouge brûlé'); end if;
  return jsonb_build_object('fine', v_fine);
end $$;

revoke all on function public.report_speeding(numeric, numeric), public.report_red_light()
  from public, anon, authenticated;
grant execute on function public.report_speeding(numeric, numeric), public.report_red_light()
  to authenticated;
