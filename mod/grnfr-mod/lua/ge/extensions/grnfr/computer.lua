-- GRNFR Online : ordinateur du garage = personnalisation du véhicule sorti (TODO point 1 de CLAUDE.md).
--
-- Pas de fenêtre séparée : c'est un écran de la tablette (Tablet.vue, app « customize »), donc les mêmes règles de
-- proximité que le reste de la tablette (grnfr_garage.isNear()) suffisent — aucune route "open"/"close" ici.
-- L'achat et l'enregistrement (pièces, réglages, peinture, stockage) sont TOUJOURS décidés et faits côté serveur
-- (supabase/migrations/0015_vehicle_customization.sql, jamais de prix côté client) ; ce module essaie seulement de
-- refléter en jeu, sur le véhicule déjà sorti, ce qui vient d'être acheté/enregistré :
--   * peinture : obj:setColor(r,g,b,a) est une API bien établie (déjà utilisée par des mods tiers) -> confiance
--     raisonnable pour la couche de base ; les couches 2/3 (setColorPalette0/1) sont une hypothèse non vérifiée.
--   * pièces et réglages : nos « slots » (moteur, jantes...) sont de simples libellés choisis par l'UI, pas de
--     vrais chemins jbeam (le serveur ne connaît pas le catalogue réel de pièces de chaque véhicule BeamNG) ; faute
--     d'accès au jeu dans cette session pour vérifier les vrais noms d'API (core_vehicle_partmgmt), l'achat est
--     fiable (argent, enregistrement, réaffichage) mais l'effet visuel/mécanique réel en jeu N'EST PAS GARANTI.
--     À vérifier en conditions réelles (voir CLAUDE.md > Hypothesis APIs) et à affiner ensuite.
local M = {}

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local function num(x) x = tonumber(x) if x and x == x then return x end end

function M.isNear() return grnfr_garage.isNear() end

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

-- parts = { [slot] = { category, part_name, price } } (tel qu'enregistré côté serveur). Tentative de repérer
-- core_vehicle_partmgmt pour un usage futur ; aucune pièce réelle n'est changée tant que les vrais noms
-- d'emplacements/pièces du jeu n'ont pas été vérifiés (voir le commentaire en tête de fichier).
function M.applyParts(vehicleId, parts)
  local o = liveObj(vehicleId)
  if not o or type(parts) ~= 'table' then return false end
  local hasPartmgmt = rawget(_G, 'core_vehicle_partmgmt') ~= nil
  slog('info', 'Computer: parts purchase saved (' .. tostring(next(parts) and 'has slots' or 'empty')
    .. '); in-game part swap not applied yet (core_vehicle_partmgmt ' .. (hasPartmgmt and 'present' or 'absent')
    .. ', unverified in this session).')
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
