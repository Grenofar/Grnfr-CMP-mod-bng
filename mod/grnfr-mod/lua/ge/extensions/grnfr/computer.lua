-- GRNFR Online : ordinateur du garage = personnalisation du véhicule sorti (TODO point 1/2bis de CLAUDE.md).
--
-- Pas de fenêtre séparée : c'est un écran de la tablette (Tablet.vue, app « customize »), donc les mêmes règles de
-- proximité que le reste de la tablette (grnfr_garage.isNear()) suffisent — aucune route "open"/"close" ici.
-- L'achat et l'enregistrement (pièces, réglages, peinture, stockage) sont TOUJOURS décidés et faits côté serveur
-- (supabase/migrations/0015_vehicle_customization.sql + 0018_vehicle_parts_catalog.sql, jamais de prix côté
-- client) ; ce module reflète en jeu ce qui vient d'être acheté/enregistré, maintenant via la VRAIE API trouvée
-- en lisant les vraies sources du jeu (BeamNG installé sur cette machine,
-- lua/ge/extensions/core/vehicle/partmgmt.lua, grand chantier Phase B, 22/10/2026) :
--   * seules 5 fonctions PUBLIQUES de core_vehicle_partmgmt changent vraiment la config (mergeConfig/
--     mergeConfigOfVehicle, qui font le travail, sont locales à ce fichier-là, donc inaccessibles) : setConfig,
--     setConfigOfVehicle, setConfigPaints, setConfigVars, setPartsTreeConfig (setPartsConfig existe mais le jeu
--     lui-même ne fait plus que logger une erreur « please use setPartsTreeConfig instead », confirmée dépréciée).
--   * peinture (setConfigPaints) : CONFIANCE RAISONNABLE — forme de données lue directement dans ge_utils.lua
--     (createVehiclePaint) : {baseColor = {r,g,b,a}, metallic, roughness, clearcoat, clearcoatRoughness}, sans
--     respawn (mergeConfigOfVehicle appelle alors vehManager.liveUpdateVehicleColors, mise à jour immédiate).
--     setConfigPaints accepte un id de véhicule explicite : fonctionne même si le joueur n'est pas assis dedans.
--   * pièces (setPartsTreeConfig) : MOYENNE CONFIANCE sur le mécanisme, INCERTAIN sur un détail. Le mécanisme :
--     mergeConfigOfVehicle fait un merge SUPERFICIEL (tableMerge, pas récursif) donc {partsTree = monArbre}
--     REMPLACE tout l'arbre existant -> on part de l'arbre RÉEL actuel (getConfig().partsTree), on y modifie
--     juste le nœud du bon emplacement (node.chosenPartName = le vrai part_key de 0018, trouvé en parcourant
--     node.children par id — structure confirmée en lisant partsTreeToPartsMap dans partmgmt.lua), puis on
--     renvoie l'arbre COMPLET. Respawn=true nécessaire (le jeu charge les nouveaux jbeam via veh:respawn(...),
--     confirmé dans mergeConfigOfVehicle). Point incertain : rien ne confirme que seul chosenPartName suffit
--     quand les enfants de ce nœud ne correspondent plus à la nouvelle pièce (on ne les reconstruit pas) — à
--     vérifier visuellement en jeu. AUCUN id de véhicule explicite dans cette fonction : elle agit sur le
--     véhicule "cible" de core_vehicle_configTarget, qui retombe sur be:getPlayerVehicleID(0) si aucune cible
--     n'est active (confirmé en lisant configTarget.lua) -> ne fonctionne que si le joueur est ASSIS dans le
--     véhicule qu'il personnalise (contrairement à la peinture). Limite connue, non résolue : retirer une pièce
--     (remove_vehicle_part) ne nous dit jamais quelle était la pièce d'origine/stock de ce slot (le serveur
--     renvoie juste `parts` sans cette clé) -> applyParts ne peut appliquer que les pièces ACHETÉES actuellement
--     présentes dans `parts`, jamais remettre une pièce stock après un retrait (aucune trace de l'originale).
--   * réglages (setConfigVars) : CONFIANCE FAIBLE sur l'effet réel. Les vraies variables jbeam de réglage
--     (ex. $brakebias, $fuel, $spoiler_angle_R, trouvées en lisant de vrais .jbeam du jeu) sont spécifiques à
--     chaque véhicule/pièce et jamais extraites dans ce projet ; nos clés ("ride", "tire", voir Tablet.vue) ne
--     correspondent presque certainement à AUCUNE vraie variable jbeam. L'appel passe par la vraie fonction
--     (mieux que ne rien faire, et un merge avec des clés inconnues ne plante rien côté jeu), mais ne doit PAS
--     être présenté comme fonctionnel avant d'avoir trouvé les vraies clés par véhicule (BeamNG.log / un .pc
--     exporté depuis le configurateur natif, désormais verrouillé en ligne — donc à faire hors ligne pour
--     inspecter, ou en lisant plus de .jbeam comme pour le catalogue de pièces).
--   * respawn : veh:respawn(...) est un appel de méthode sur l'objet EXISTANT (pas une recréation côté manager) ;
--     selon toute probabilité le véhicule garde le même id après, mais ceci reste une hypothèse, jamais vérifié
--     dans le vrai jeu.
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

-- Utilisé autour de nos PROPRES appels à core_vehicle_partmgmt (applyPaint/applyParts/applyTuning ci-dessous) :
-- fn() s'exécute avec le verrou désactivé, pour que nos appels à travers les 5 fonctions enveloppées passent.
local function withLockDisabled(fn)
  local prev = applying
  applying = true
  local ok, err = pcall(fn)
  applying = prev
  if not ok then slog('warn', 'Computer: error while applying our own config change: ' .. tostring(err)) end
  return ok
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

-- Construit un objet "paint" dans le VRAI format du jeu (ge_utils.lua, createVehiclePaint) : métallique/rugosité/
-- vernis fixés aux mêmes valeurs par défaut que le jeu applique quand on ne les précise pas (notre UI ne propose
-- que la couleur de base, pas ces réglages avancés).
local function realPaint(c)
  local r, g, b, a = layer(c)
  return { baseColor = { r, g, b, a }, metallic = 0.2, roughness = 0.5, clearcoat = 0.8, clearcoatRoughness = 0.0 }
end

-- paint = { {r,g,b,a}, {r,g,b,a}?, {r,g,b,a}? } (0..1, jusqu'à 3 couches comme le jeu). Renvoie true si l'appel à
-- la vraie API (core_vehicle_partmgmt.setConfigPaints) a pu être fait sans erreur.
function M.applyPaint(vehicleId, paint)
  local o = liveObj(vehicleId)
  if not o or type(paint) ~= 'table' or not paint[1] then return false end
  local pm = rawget(_G, 'core_vehicle_partmgmt')
  if not pm or type(pm.setConfigPaints) ~= 'function' then return false end
  local vehId
  pcall(function() vehId = o:getID() end)
  if not vehId then return false end

  local paints = {}
  for i = 1, 3 do if paint[i] then paints[i] = realPaint(paint[i]) end end

  local ok = withLockDisabled(function()
    pm.setConfigPaints(paints, false, vehId) -- respawn=false : mise à jour immédiate (vehManager.liveUpdateVehicleColors)
  end)
  if ok then slog('info', 'Computer: repainted the vehicle in game via setConfigPaints (' .. #paints .. ' layer(s)).') end
  return ok
end

-- Cherche récursivement, dans un arbre de pièces (partsTree), le nœud d'un emplacement donné (slotId = la clé
-- dans node.children, structure confirmée en lisant partsTreeToPartsMap/flattenPartsTreeRecursive dans le vrai
-- partmgmt.lua du jeu).
local function findSlotNode(node, slotId)
  if type(node) ~= 'table' or type(node.children) ~= 'table' then return nil end
  local direct = node.children[slotId]
  if direct then return direct end
  for _, child in pairs(node.children) do
    local found = findSlotNode(child, slotId)
    if found then return found end
  end
  return nil
end

-- parts = { [slot] = { part_key, name, price } } (vrais identifiants jbeam, 0018_vehicle_parts_catalog.sql) :
-- l'état COMPLET des pièces achetées sur ce véhicule (pas une liste de changements), envoyé par Tablet.vue après
-- chaque achat/retrait. On relit l'arbre RÉEL actuel du véhicule (core_vehicle_partmgmt.getConfig()), on y pose
-- chosenPartName pour chaque emplacement qu'on reconnaît, puis on renvoie l'arbre complet via setPartsTreeConfig
-- (respawn=true, seul moyen connu de faire charger les nouveaux jbeam). Ne fonctionne que si le joueur est assis
-- dans le véhicule configuré (cette fonction du jeu n'accepte pas d'id explicite, voir le commentaire en tête de
-- fichier) ; ne peut pas remettre une pièce stock après un retrait (le serveur ne nous dit jamais laquelle
-- c'était). Retourne true seulement si au moins un emplacement a été retrouvé et appliqué sans erreur.
function M.applyParts(vehicleId, parts)
  local o = liveObj(vehicleId)
  if not o or type(parts) ~= 'table' then return false end
  local pm = rawget(_G, 'core_vehicle_partmgmt')
  if not pm or type(pm.getConfig) ~= 'function' or type(pm.setPartsTreeConfig) ~= 'function' then return false end

  local tried, applied, lastPart = 0, 0, nil
  local ok = withLockDisabled(function()
    local cfg = pm.getConfig()
    if type(cfg) ~= 'table' or type(cfg.partsTree) ~= 'table' then
      error('pas de partsTree (le joueur n\'est probablement pas assis dans ce véhicule)')
    end
    local tree = deepcopy(cfg.partsTree)
    for slot, info in pairs(parts) do
      local partKey = type(info) == 'table' and info.part_key or nil
      if partKey then
        tried = tried + 1
        local node = findSlotNode(tree, slot)
        if node then
          node.chosenPartName = partKey
          applied = applied + 1
          lastPart = partKey
        end
      end
    end
    if applied > 0 then
      pm.setPartsTreeConfig(tree, true, lastPart)
    else
      error('aucun des ' .. tried .. ' emplacement(s) acheté(s) n\'a été retrouvé dans l\'arbre de pièces réel')
    end
  end)
  slog('info', 'Computer: parts -- ' .. tried .. ' bought slot(s), ' .. applied .. ' found in the real partsTree, '
    .. 'setPartsTreeConfig ' .. (ok and 'called (respawn) ' or 'NOT called ')
    .. '-- effet réel non confirmé en jeu, voir le commentaire en tête de fichier.')
  return ok and applied > 0
end

-- tuning = table de réglages numériques libres (hauteur de caisse, pression des pneus — voir Tablet.vue). Appelle
-- la vraie fonction (core_vehicle_partmgmt.setConfigVars) mais AUCUNE vraie clé de variable jbeam par véhicule
-- n'a été trouvée pour "ride"/"tire" dans cette session (voir le commentaire en tête de fichier) : l'enregistrement
-- serveur est fiable, l'appel passe par la bonne API, mais l'effet en jeu est très probablement nul jusqu'à ce que
-- les vraies clés soient identifiées (BeamNG.log / inspection de .jbeam par véhicule, comme pour le catalogue de
-- pièces) -- ne pas présenter ceci comme fonctionnel avant d'avoir vérifié visuellement en jeu.
function M.applyTuning(vehicleId, tuning)
  if not liveObj(vehicleId) then return false end
  local pm = rawget(_G, 'core_vehicle_partmgmt')
  if not pm or type(pm.setConfigVars) ~= 'function' or type(tuning) ~= 'table' then return false end
  local ok = withLockDisabled(function() pm.setConfigVars(tuning, true) end)
  slog('info', 'Computer: tuning saved server-side; setConfigVars called (' .. (ok and 'no error' or 'error')
    .. ') but the real jbeam variable names are still unknown -- likely no visible effect, see file header.')
  return ok
end

return M
