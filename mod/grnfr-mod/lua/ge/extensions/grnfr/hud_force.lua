-- GRNFR Online : force le HUD natif complet (minimap, vitesse, etc.) tant qu'on est connecté à un serveur
-- GRNFR, indépendamment de la disposition personnelle du joueur (Options > HUD Apps) -- demandé explicitement
-- par l'utilisateur (23/10/2026).
--
-- Vraie API trouvée en lisant les sources du jeu (BeamNG installé sur cette machine,
-- lua/ge/extensions/ui/appLayouts.lua, extension publique "ui_appLayouts", confirmée utilisée sous ce nom par
-- lua/ge/extensions/ui/apps.lua) : getAvailableLayouts()/getCurrentLayout()/setCurrentLayout(layoutOuNom).
-- setCurrentLayout (PAS setUsedLayout) est utilisée volontairement : setUsedLayout enregistre le choix comme
-- préférence PERMANENTE pour le type "freeroam" (y compris hors de nos serveurs, en carrière solo...) --
-- setCurrentLayout ne change que l'affichage courant, sans toucher aux réglages du joueur. Sa disposition
-- personnelle est sauvegardée avant de forcer la nôtre, et restaurée dès qu'il quitte le serveur.
--
-- La disposition visée est la VRAIE disposition "freeroam" par défaut du jeu (settings/ui_apps/originalLayouts/
-- default/freeroam.uilayout.json, confirmée par lecture directe : contient déjà "navigation" = minimap et
-- "tacho2" = compteur de vitesse) -- pas une disposition inventée par nous, retrouvée via la vraie API publique
-- getAvailableLayouts() plutôt qu'un chemin de fichier deviné.
local M = {}

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

local saved, applied = nil, false

local function appLayouts() return rawget(_G, 'extensions') and extensions.ui_appLayouts end

local function defaultFreeroamLayout()
  local al = appLayouts()
  if not al or type(al.getAvailableLayouts) ~= 'function' then return nil end
  local ok, layouts = pcall(al.getAvailableLayouts)
  if not ok or type(layouts) ~= 'table' then return nil end
  local fallback
  for _, l in ipairs(layouts) do
    if l.type == 'freeroam' then
      if l.default == true then return l end
      fallback = fallback or l
    end
  end
  return fallback
end

local function lockActive()
  local o = rawget(_G, 'grnfr_online')
  local gh = rawget(_G, 'grnfr_ghosts')
  return o and o.isAuthed and o.isAuthed() and gh and gh.status and gh.status().joined == true
end

function M.update()
  local al = appLayouts()
  if not al or type(al.setCurrentLayout) ~= 'function' then return end
  local active = lockActive()
  if active and not applied then
    if type(al.getCurrentLayout) == 'function' then
      local ok, cur = pcall(al.getCurrentLayout)
      if ok and type(cur) == 'table' then saved = cur end
    end
    local target = defaultFreeroamLayout()
    if target then
      local ok = pcall(al.setCurrentLayout, target)
      if ok then
        applied = true
        slog('info', 'HUD: forced the default freeroam layout (minimap, speed) while online.')
      end
    end
  elseif not active and applied then
    if saved then pcall(al.setCurrentLayout, saved) end
    applied, saved = false, nil
    slog('info', 'HUD: restored your own HUD layout after leaving the server.')
  end
end

return M
