-- GRNFR Online : ordinateur du garage = personnalisation du véhicule sorti (TODO point 1 de CLAUDE.md).
--
-- Pas de fenêtre séparée : c'est un écran de la tablette (Tablet.vue, app « customize »), donc les mêmes règles de
-- proximité que le reste de la tablette (grnfr_garage.isNear()) suffisent — aucune route "open"/"close" ici.
-- L'achat et l'enregistrement (pièces, réglages, peinture, stockage) sont TOUJOURS décidés et faits côté serveur
-- (supabase/migrations/0015_vehicle_customization.sql, jamais de prix côté client) ; ce module essaie seulement de
-- refléter en jeu, sur le véhicule déjà sorti, ce qui vient d'être acheté/enregistré :
--   * peinture : obj:setColor(r,g,b,a) est une API bien établie (déjà utilisée par des mods tiers) -> confiance
--     raisonnable pour la couche de base ; les couches 2/3 (setColorPalette0/1) sont une hypothèse non vérifiée.
--   * pièces : depuis 0018_vehicle_parts_catalog.sql, "slot" et "part_key" sont de VRAIS identifiants jbeam
--     (extraits des fichiers du jeu par scripts/extract-parts-catalog.mjs), donc un vrai nom à passer à
--     core_vehicle_partmgmt si cette API existe sous cette forme ; mais aucune de ses fonctions exactes
--     (setPart ? setPartsConfig ? getConfig ?) n'a été vérifiée dans cette session (pas d'accès au jeu) : l'achat
--     est fiable (argent, enregistrement, réaffichage côté tablette), l'effet réel en jeu NE L'EST PAS — un appel
--     qui ne lève pas d'erreur ne prouve pas que la pièce a changé. À vérifier en conditions réelles (voir
--     CLAUDE.md > Hypothesis APIs) et à corriger ici une fois les vraies fonctions connues (BeamNG.log).
local M = {}

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local function num(x) x = tonumber(x) if x and x == x then return x end end
local function online() return rawget(_G, 'grnfr_online') end
local function L(fr, en) local o = online() return o and o.L(fr, en) or fr end
local function toast(m, k) local o = online() if o then o.toast(m, k) end end

function M.isNear() return grnfr_garage.isNear() end

-- ------------------------------------------------------------------ verrouillage de la config native (grand
-- chantier Phase B, 22/10/2026) : tant qu'on est en ligne GRNFR, toute pièce/réglage/peinture doit passer par
-- CET ordinateur, jamais par le configurateur natif du jeu (menu Échap ou sélecteur de véhicule). Découverte en
-- lisant les vraies sources du jeu (BeamNG installé sur cette machine,
-- lua/ge/extensions/core/vehicle/partmgmt.lua) : TOUT changement de pièces/vars/peinture passe forcément par une
-- de ces 5 fonctions PUBLIQUES de core_vehicle_partmgmt (les fonctions qui font le vrai travail, mergeConfig/
-- mergeConfigOfVehicle, sont locales à ce fichier et donc inaccessibles depuis l'extérieur) : setConfig,
-- setConfigOfVehicle, setConfigPaints, setConfigVars, setPartsTreeConfig (setPartsConfig existe mais le jeu lui-
-- même ne fait plus que logger une erreur, dépréciée). On les remplace chacune par une enveloppe qui laisse
-- passer l'appel UNIQUEMENT si CE module vient de l'appeler lui-même (drapeau `applying`, posé juste autour de
-- nos propres appels) ; sinon, si on est en ligne GRNFR, l'appel est bloqué (retourne nil sans rien faire) et un
-- message explique pourquoi. Hors ligne (carrière solo, etc.), rien n'est bloqué.
-- Risque connu : si le jeu appelle une AUTRE fonction encore pour changer la config (non trouvée dans cette
-- lecture du code), elle ne serait pas couvrue -- à revérifier avec le BeamNG.log si un joueur arrive malgré tout
-- à configurer nativement pendant qu'il est en ligne.
local ENTRY_POINTS = { 'setConfig', 'setConfigOfVehicle', 'setConfigPaints', 'setConfigVars', 'setPartsTreeConfig' }
local hooked, applying = false, false

local function lockActive()
  local o = online()
  local gh = rawget(_G, 'grnfr_ghosts')
  return o and o.isAuthed() and gh and gh.status and gh.status().joined == true
end

local function tryInstallLock()
  if hooked then return end
  local pm = rawget(_G, 'core_vehicle_partmgmt')
  if not pm then return end
  hooked = true
  for _, name in ipairs(ENTRY_POINTS) do
    local orig = pm[name]
    if type(orig) == 'function' then
      pm[name] = function(...)
        if applying or not lockActive() then return orig(...) end
        toast(L('Configuration bloquée : utilisez l\'ordinateur du garage GRNFR CMP.',
          'Configuration blocked: use the GRNFR CMP garage computer.'), 'warning')
        slog('warn', 'Computer: blocked a native vehicle configuration call (' .. name .. ') while online.')
        return nil
      end
    end
  end
  slog('info', 'Computer: native vehicle configuration is now locked while online (GRNFR computer only, lockdown installed).')
end

-- Appelé à chaque image par grnfr.lua (M.tick) : installe le verrou dès que core_vehicle_partmgmt existe (ordre
-- de chargement des extensions non garanti), puis ne fait plus rien (hooked = true).
function M.update() pcall(tryInstallLock) end

-- À utiliser autour de nos PROPRES appels à core_vehicle_partmgmt, une fois que applyParts/applyPaint/applyTuning
-- les utiliseront vraiment (pas encore le cas, voir plus bas) : fn() s'exécute avec le verrou désactivé.
local function withLockDisabled(fn)
  local prev = applying
  applying = true
  local ok, err = pcall(fn)
  applying = prev
  if not ok then slog('warn', 'Computer: error while applying our own config change: ' .. tostring(err)) end
end
M.withLockDisabled = withLockDisabled

local function liveObj(vehicleId)
  local sp = grnfr_online.spawnedList()
  local s = sp and sp[vehicleId]
  if not s then return nil end
  local ok, o = pcall(function() return be:getObjectByID(s.obj) end)
  if ok then return o end
end

local function layer(c)
  if type(c) ~= 'table' then return 1, 1, 1, 1 end
  return num(c.r) or 1, num(c.g) or 1, num(c.b) or 1, num(c.a) or 1
end

-- paint = { {r,g,b,a}, {r,g,b,a}?, {r,g,b,a}? } (0..1, jusqu'à 3 couches comme le jeu). Renvoie true si au moins la
-- couche de base a pu être appliquée.
function M.applyPaint(vehicleId, paint)
  local o = liveObj(vehicleId)
  if not o or type(paint) ~= 'table' or not paint[1] then return false end
  local ok = pcall(function() local r, g, b, a = layer(paint[1]) o:setColor(r, g, b, a) end)
  if not ok then slog('warn', 'Computer: setColor failed, the paint was only saved server-side.') return false end
  if paint[2] then pcall(function() local r, g, b, a = layer(paint[2]) o:setColorPalette0(r, g, b, a) end) end
  if paint[3] then pcall(function() local r, g, b, a = layer(paint[3]) o:setColorPalette1(r, g, b, a) end) end
  slog('info', 'Computer: repainted the vehicle in game (base layer at least).')
  return true
end

-- parts = { [slot] = { part_key, name, price } } (vrais identifiants jbeam, 0018_vehicle_parts_catalog.sql).
-- Essaie plusieurs formes d'appel à core_vehicle_partmgmt (aucune vérifiée en jeu) ; ne pas dire "ça a marché"
-- juste parce qu'aucune n'a levé d'erreur — seul un essai en jeu réel (BeamNG.log) peut le confirmer.
function M.applyParts(vehicleId, parts)
  local o = liveObj(vehicleId)
  if not o or type(parts) ~= 'table' then return false end
  local vehId
  pcall(function() vehId = o:getID() end)
  local tried, noError = 0, 0
  for slot, info in pairs(parts) do
    local partKey = type(info) == 'table' and info.part_key or nil
    if partKey and vehId then
      tried = tried + 1
      local ok = pcall(function()
        if core_vehicle_partmgmt and core_vehicle_partmgmt.setPart then
          core_vehicle_partmgmt.setPart(vehId, slot, partKey)
        elseif core_vehicle_partmgmt and core_vehicle_partmgmt.setPartsConfig and core_vehicle_partmgmt.getConfig then
          local cfg = core_vehicle_partmgmt.getConfig(vehId)
          if type(cfg) ~= 'table' then error('no config') end
          cfg.parts = cfg.parts or {}
          cfg.parts[slot] = partKey
          core_vehicle_partmgmt.setPartsConfig(vehId, cfg)
        else
          error('core_vehicle_partmgmt not usable here')
        end
      end)
      if ok then noError = noError + 1 end
    end
  end
  slog('info', 'Computer: parts purchase saved server-side; tried to apply ' .. tried .. ' part(s) in game, '
    .. noError .. ' call(s) did not error (core_vehicle_partmgmt function names unverified — not erroring is '
    .. 'NOT proof the part actually changed, check visually/in BeamNG.log).')
  return true
end

-- tuning = table de réglages numériques libres (hauteur de caisse, pression des pneus...). Enregistré côté serveur
-- uniquement pour l'instant ; non encore réappliqué en jeu (API non vérifiée, voir le commentaire en tête de fichier).
function M.applyTuning(vehicleId, tuning)
  if not liveObj(vehicleId) then return false end
  slog('info', 'Computer: tuning saved server-side; in-game application not verified yet.')
  return true
end

return M
