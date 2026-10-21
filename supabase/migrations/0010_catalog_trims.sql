-- =====================================================================================
-- GRNFR Online - 0010 : plusieurs configurations (modèles/finitions) par véhicule au
-- concessionnaire, avec de vrais prix très différents (comme dans le jeu de base). Jusqu'ici
-- chaque véhicule n'avait qu'UNE ligne (sa configuration par défaut, prix corrigé en 0009).
--
-- Pour chaque véhicule : 3 finitions supplémentaires (la moins chère, une intermédiaire, la
-- plus chère parmi les configurations du jeu), avec le prix réel ("Value") lu dans les fichiers
-- du jeu (BeamNG.drive) pour cette configuration précise — pas une estimation.
-- À exécuter APRÈS 0001-0009 (Supabase > SQL Editor > Run).
-- =====================================================================================

insert into public.dealership_catalog (model_key, config_key, name, price)
select * from (values
  ('covet',     'covet_tutorial',               'Ibishu Covet — covet_tutorial',               12000::bigint),
  ('covet',     '15zxi_M',                       'Ibishu Covet — 15zxi_M',                       27500),
  ('covet',     'turbo_rally',                   'Ibishu Covet — turbo_rally',                   145000),

  ('pessima',   'DX_A',                          'Ibishu Pessima — DX_A',                        24300),
  ('pessima',   'GTz',                           'Ibishu Pessima — GTz',                         49000),
  ('pessima',   'hillclimb',                     'Ibishu Pessima — hillclimb',                   204500),

  ('sunburst2', 'base_EU_M',                     'Hirochi Sunburst — base_EU_M',                 25500),
  ('sunburst2', 'sport_S_wagon_DCT',             'Hirochi Sunburst — sport_S_wagon_DCT',          38300),
  ('sunburst2', 'track_attack',                  'Hirochi Sunburst — track_attack',              120000),

  ('vivace',    'vivace_110_M',                  'Cherrier Vivace — vivace_110_M',                23500),
  ('vivace',    'vivace_S_270_DCT',             'Cherrier Vivace — vivace_S_270_DCT',             46000),
  ('vivace',    'ardente_rally',                 'Cherrier Vivace — ardente_rally',               203600),

  ('miramar',   'base_facelift_M',               'Ibishu Miramar — base_facelift_M',              25500),
  ('miramar',   'luxe_coupe_export_early_A',    'Ibishu Miramar — luxe_coupe_export_early_A',    30500),
  ('miramar',   'miramighty',                    'Ibishu Miramar — miramighty',                   135000),

  ('pickup',    'd15_fleet_M_facelift',         'Gavril D-Series — d15_fleet_M_facelift',        31000),
  ('pickup',    'd25_ext_longbed_4wd_A_facelift','Gavril D-Series — d25_ext_longbed_4wd_A_facelift', 57500),
  ('pickup',    'deserttruck_prerunner_A',      'Gavril D-Series — deserttruck_prerunner_A',     230000),

  ('etk800',    '844_150_M',                     'ETK 800 Series — 844_150_M',                    34000),
  ('etk800',    '856xc_300_A',                   'ETK 800 Series — 856xc_300_A',                  58500),
  ('etk800',    '846_ttSport_custom_DCT',       'ETK 800 Series — 846_ttSport_custom_DCT',       198000),

  ('bastion',   'base_v6_awd_A',                 'Bruckell Bastion — base_v6_awd_A',               37500),
  ('bastion',   'police_v8_awd_A',               'Bruckell Bastion — police_v8_awd_A',             50500),
  ('bastion',   'drag',                          'Bruckell Bastion — drag',                        138500),

  ('barstow',   'i6a',                           'Gavril Barstow — i6a',                           34000),
  ('barstow',   '423a',                          'Gavril Barstow — 423a',                          48000),
  ('barstow',   'drag',                          'Gavril Barstow — drag',                          165000),

  ('moonhawk',  'i6m',                           'Bruckell Moonhawk — i6m',                        36000),
  ('moonhawk',  'detective',                     'Bruckell Moonhawk — detective',                  52000),
  ('moonhawk',  'drag',                          'Bruckell Moonhawk — drag',                       142000),

  ('bolide',    'polizia',                       'Civetta Bolide — polizia',                       181000),
  ('bolide',    '320gtt_us',                     'Civetta Bolide — 320gtt_us',                     295000),
  ('bolide',    'race',                          'Civetta Bolide — race',                          490000),

  ('scintilla', 'gt',                            'Civetta Scintilla — gt',                         180000),
  ('scintilla', 'custom',                        'Civetta Scintilla — custom',                     304000),
  ('scintilla', 'race',                          'Civetta Scintilla — race',                       615000),

  ('fullsize',  'fleet',                         'Gavril Grand Marshal — fleet',                   39900),
  ('fullsize',  'drift',                         'Gavril Grand Marshal — drift',                   77000),
  ('fullsize',  'track',                         'Gavril Grand Marshal — track',                   165000),

  ('citybus',   'base',                          'Wentward DT40L (bus) — base',                    400000),
  ('citybus',   'highway',                       'Wentward DT40L (bus) — highway',                 460000),
  ('citybus',   'rambus',                        'Wentward DT40L (bus) — rambus',                   835000)
) as v(model_key, config_key, name, price)
where not exists (
  select 1 from public.dealership_catalog c where c.model_key = v.model_key and c.config_key = v.config_key
);
