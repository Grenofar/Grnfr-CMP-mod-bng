-- =====================================================================================
-- GRNFR Online - REMET LES DONNÉES DE DÉPART (réglages du serveur + catalogue du concessionnaire).
-- À utiliser après wipe_all.sql, ou n'importe quand : tout ici utilise "on conflict do nothing" /
-- "where not exists", donc ça ne touche jamais une ligne déjà présente (sans danger sur une base
-- qui a déjà des joueurs). Ce n'est PAS une migration numérotée : ne la mettez pas dans
-- supabase/migrations/. Suppose que le schéma existe déjà (0001 à 0011 déjà appliquées une fois).
-- =====================================================================================

-- ------------------------------------------------------------------ réglages (0001, 0002, 0007)
insert into public.server_config (key, value, description) values
  ('starting_money',            '25000',  'Argent donné à l''inscription'),
  ('garage_slots',              '4',      'Places de garage par joueur (défaut)'),
  ('market_fee_percent',        '5',      'Commission prélevée sur les ventes privées (%)'),
  ('dealer_buyback_percent',    '50',     'Rachat d''un véhicule par le concessionnaire (% de sa valeur)'),
  ('max_transfer',              '1000000','Plafond d''un envoi d''argent entre joueurs'),
  ('max_listing_price',         '5000000','Prix maximum d''une annonce'),
  ('taxi_base_fare',            '8',      'Taxi : prise en charge'),
  ('taxi_per_km',               '3',      'Taxi : prix au km'),
  ('taxi_fee_percent',          '0',      'Taxi : commission du serveur sur les courses entre joueurs (%)'),
  ('taxi_request_ttl_seconds',  '180',    'Durée de vie d''une demande de taxi sans chauffeur'),
  ('bot_taxi_multiplier',       '1.5',    'Taxi IA : multiplicateur de prix'),
  ('bus_base_per_passenger',    '3',      'Bus : prix de base par passager'),
  ('bus_per_passenger_per_km',  '2',      'Bus : prix au km par passager'),
  ('npc_income_cap_per_hour',   '6000',   'Plafond de gains/heure venant du serveur (taxi PNJ, bus) : limite la triche'),
  ('max_speed_mps',             '60',     'Vitesse max crédible (m/s) pour valider la durée d''une course'),
  ('member_timeout_seconds',    '30',     'Un joueur sans signal depuis ce délai (s) libère sa place sur le serveur de jeu'),
  ('sync_interval_ms',          '300',    'Cadence d''envoi de la position au serveur (ms). Mini 150.'),
  ('drag_min_distance_m',       '100',    'Longueur minimum d''une course de drag (m)'),
  ('drag_max_distance_m',       '3000',   'Longueur maximum d''une course de drag (m)'),
  ('drag_max_speed_mps',        '100',    'Vitesse moyenne max crédible pour valider un temps de drag (m/s)'),
  ('drag_min_stake',            '100',    'Mise minimum pour une course de drag'),
  ('drag_max_stake',            '50000',  'Mise maximum pour une course de drag'),
  ('delivery_base_fare',             '40',  'Livraison : prise en charge'),
  ('delivery_per_km',                '4',   'Livraison : prix au km'),
  ('delivery_per_unit',              '15',  'Livraison : prix par unité de capacité cargo demandée'),
  ('delivery_max_active_per_level',  '15',  'Livraison : nombre maximum d''offres disponibles en même temps par carte'),
  ('delivery_offer_ttl_minutes',     '30',  'Livraison : durée de vie d''une offre non acceptée (minutes)'),
  ('employee_hire_cost',             '5000', 'Salarié : coût d''embauche (une fois)'),
  ('employee_speed_kmh',             '60',   'Salarié : vitesse virtuelle (km/h) utilisée pour faire avancer sa progression en temps réel'),
  ('employee_income_per_100km',      '500',  'Salarié : revenu généré tous les 100 km parcourus'),
  ('employee_wage_per_100km',        '200',  'Salarié : salaire payé tous les 100 km parcourus (déduit du revenu ci-dessus)'),
  ('employee_max_tick_seconds',      '120',  'Salarié : écart de temps réel maximum accepté par mise à jour (protège contre une longue coupure/reconnexion)'),
  ('radar_fine_base',                '50',   'Radar : amende de base pour excès de vitesse'),
  ('radar_fine_per_kmh_over',        '5',    'Radar : amende supplémentaire par km/h au-dessus de la limite'),
  ('radar_max_speed_kmh',            '300',  'Radar : vitesse maximum plausible acceptée du client (sécurité)'),
  ('redlight_fine',                  '150',  'Feu rouge : amende fixe'),
  ('fine_cooldown_seconds',          '20',   'Radars/feux rouges : délai minimum entre deux amendes pour un même joueur')
on conflict (key) do nothing;

-- ------------------------------------------------------------------ catalogue de base (0001)
insert into public.dealership_catalog (model_key, config_key, name, price)
select * from (values
  ('covet',     null::text, 'Ibishu Covet',          19000::bigint),
  ('pessima',   null,       'Ibishu Pessima',        27700),
  ('sunburst2', null,       'Hirochi Sunburst',      25500),
  ('vivace',    null,       'Cherrier Vivace',       74400),
  ('miramar',   null,       'Ibishu Miramar',        24500),
  ('pickup',    null,       'Gavril D-Series',       44500),
  ('etk800',    null,       'ETK 800 Series',        43000),
  ('bastion',   null,       'Bruckell Bastion',      34500),
  ('barstow',   null,       'Gavril Barstow',        45000),
  ('moonhawk',  null,       'Bruckell Moonhawk',     48000),
  ('bolide',    null,       'Civetta Bolide',        180000),
  ('scintilla', null,       'Civetta Scintilla',     205000),
  ('fullsize',  null,       'Gavril Grand Marshal',  43000),
  ('citybus',   null,       'Wentward DT40L (bus)',  450000)
) as v(model_key, config_key, name, price)
where not exists (select 1 from public.dealership_catalog c where c.model_key = v.model_key and c.config_key is null);

-- ------------------------------------------------------------------ finitions du catalogue (0010)
insert into public.dealership_catalog (model_key, config_key, name, price)
select * from (values
  ('covet',     'covet_tutorial',                'Ibishu Covet — covet_tutorial',                 12000::bigint),
  ('covet',     '15zxi_M',                        'Ibishu Covet — 15zxi_M',                        27500),
  ('covet',     'turbo_rally',                    'Ibishu Covet — turbo_rally',                    145000),
  ('pessima',   'DX_A',                           'Ibishu Pessima — DX_A',                         24300),
  ('pessima',   'GTz',                            'Ibishu Pessima — GTz',                          49000),
  ('pessima',   'hillclimb',                      'Ibishu Pessima — hillclimb',                    204500),
  ('sunburst2', 'base_EU_M',                      'Hirochi Sunburst — base_EU_M',                  25500),
  ('sunburst2', 'sport_S_wagon_DCT',              'Hirochi Sunburst — sport_S_wagon_DCT',          38300),
  ('sunburst2', 'track_attack',                   'Hirochi Sunburst — track_attack',               120000),
  ('vivace',    'vivace_110_M',                   'Cherrier Vivace — vivace_110_M',                23500),
  ('vivace',    'vivace_S_270_DCT',               'Cherrier Vivace — vivace_S_270_DCT',            46000),
  ('vivace',    'ardente_rally',                  'Cherrier Vivace — ardente_rally',                203600),
  ('miramar',   'base_facelift_M',                'Ibishu Miramar — base_facelift_M',              25500),
  ('miramar',   'luxe_coupe_export_early_A',      'Ibishu Miramar — luxe_coupe_export_early_A',    30500),
  ('miramar',   'miramighty',                     'Ibishu Miramar — miramighty',                   135000),
  ('pickup',    'd15_fleet_M_facelift',           'Gavril D-Series — d15_fleet_M_facelift',        31000),
  ('pickup',    'd25_ext_longbed_4wd_A_facelift', 'Gavril D-Series — d25_ext_longbed_4wd_A_facelift', 57500),
  ('pickup',    'deserttruck_prerunner_A',        'Gavril D-Series — deserttruck_prerunner_A',     230000),
  ('etk800',    '844_150_M',                      'ETK 800 Series — 844_150_M',                    34000),
  ('etk800',    '856xc_300_A',                    'ETK 800 Series — 856xc_300_A',                  58500),
  ('etk800',    '846_ttSport_custom_DCT',         'ETK 800 Series — 846_ttSport_custom_DCT',       198000),
  ('bastion',   'base_v6_awd_A',                  'Bruckell Bastion — base_v6_awd_A',              37500),
  ('bastion',   'police_v8_awd_A',                'Bruckell Bastion — police_v8_awd_A',            50500),
  ('bastion',   'drag',                           'Bruckell Bastion — drag',                       138500),
  ('barstow',   'i6a',                            'Gavril Barstow — i6a',                          34000),
  ('barstow',   '423a',                           'Gavril Barstow — 423a',                         48000),
  ('barstow',   'drag',                           'Gavril Barstow — drag',                         165000),
  ('moonhawk',  'i6m',                            'Bruckell Moonhawk — i6m',                       36000),
  ('moonhawk',  'detective',                      'Bruckell Moonhawk — detective',                 52000),
  ('moonhawk',  'drag',                           'Bruckell Moonhawk — drag',                      142000),
  ('bolide',    'polizia',                        'Civetta Bolide — polizia',                      181000),
  ('bolide',    '320gtt_us',                      'Civetta Bolide — 320gtt_us',                    295000),
  ('bolide',    'race',                           'Civetta Bolide — race',                         490000),
  ('scintilla', 'gt',                             'Civetta Scintilla — gt',                        180000),
  ('scintilla', 'custom',                         'Civetta Scintilla — custom',                    304000),
  ('scintilla', 'race',                           'Civetta Scintilla — race',                      615000),
  ('fullsize',  'fleet',                          'Gavril Grand Marshal — fleet',                  39900),
  ('fullsize',  'drift',                          'Gavril Grand Marshal — drift',                  77000),
  ('fullsize',  'track',                          'Gavril Grand Marshal — track',                  165000),
  ('citybus',   'base',                           'Wentward DT40L (bus) — base',                   400000),
  ('citybus',   'highway',                        'Wentward DT40L (bus) — highway',                460000),
  ('citybus',   'rambus',                         'Wentward DT40L (bus) — rambus',                  835000)
) as v(model_key, config_key, name, price)
where not exists (select 1 from public.dealership_catalog c where c.model_key = v.model_key and c.config_key = v.config_key);

-- ------------------------------------------------------------------ classes perf/confort (0023) : toujours
-- réappliquées (pas de "on conflict"/"where not exists" ici), pour que les colonnes gardent leurs vraies valeurs
-- même sur un catalogue déjà peuplé — sans ça, les lignes insérées ci-dessus garderaient le défaut 3/3.
with classes (model_key, config_key, perf, comfort) as (
  values
    ('barstow',   'i6a',                              2, 3),
    ('barstow',   null,                                3, 3),
    ('barstow',   '423a',                              4, 3),
    ('barstow',   'drag',                              5, 1),
    ('bastion',   null,                                3, 4),
    ('bastion',   'base_v6_awd_A',                     4, 4),
    ('bastion',   'police_v8_awd_A',                   4, 3),
    ('bastion',   'drag',                              5, 1),
    ('bolide',    null,                                5, 2),
    ('bolide',    'polizia',                           5, 2),
    ('bolide',    '320gtt_us',                         5, 1),
    ('bolide',    'race',                              5, 1),
    ('citybus',   'base',                               1, 4),
    ('citybus',   null,                                1, 4),
    ('citybus',   'highway',                           1, 5),
    ('citybus',   'rambus',                            2, 2),
    ('covet',     'covet_tutorial',                    1, 2),
    ('covet',     null,                                2, 3),
    ('covet',     '15zxi_M',                           3, 3),
    ('covet',     'turbo_rally',                       5, 1),
    ('etk800',    '844_150_M',                         2, 4),
    ('etk800',    null,                                3, 4),
    ('etk800',    '856xc_300_A',                       4, 5),
    ('etk800',    '846_ttSport_custom_DCT',            5, 3),
    ('fullsize',  'fleet',                             2, 3),
    ('fullsize',  null,                                2, 4),
    ('fullsize',  'drift',                             4, 2),
    ('fullsize',  'track',                             5, 1),
    ('miramar',   null,                                2, 3),
    ('miramar',   'base_facelift_M',                   2, 3),
    ('miramar',   'luxe_coupe_export_early_A',         3, 4),
    ('miramar',   'miramighty',                        3, 1),
    ('moonhawk',  'i6m',                               2, 3),
    ('moonhawk',  null,                                4, 3),
    ('moonhawk',  'detective',                         3, 3),
    ('moonhawk',  'drag',                              5, 1),
    ('pessima',   'DX_A',                              2, 4),
    ('pessima',   null,                                2, 4),
    ('pessima',   'GTz',                               4, 3),
    ('pessima',   'hillclimb',                         5, 1),
    ('pickup',    'd15_fleet_M_facelift',              1, 2),
    ('pickup',    null,                                2, 3),
    ('pickup',    'd25_ext_longbed_4wd_A_facelift',    2, 3),
    ('pickup',    'deserttruck_prerunner_A',           5, 1),
    ('scintilla', 'gt',                                5, 2),
    ('scintilla', null,                                5, 2),
    ('scintilla', 'custom',                            5, 1),
    ('scintilla', 'race',                              5, 1),
    ('sunburst2', 'base_EU_M',                         2, 3),
    ('sunburst2', 'sport_S_wagon_DCT',                 3, 3),
    ('sunburst2', null,                                3, 4),
    ('sunburst2', 'track_attack',                      5, 1),
    ('vivace',    'vivace_110_M',                      1, 3),
    ('vivace',    'vivace_S_270_DCT',                  4, 2),
    ('vivace',    null,                                2, 4),
    ('vivace',    'ardente_rally',                     5, 1)
)
update public.dealership_catalog c set perf_class = classes.perf, comfort_class = classes.comfort
from classes
where c.model_key = classes.model_key and coalesce(c.config_key, '') = coalesce(classes.config_key, '');
