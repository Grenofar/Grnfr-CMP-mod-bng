-- GRNFR Online : bloque, tant qu'on est en ligne sur un serveur GRNFR, deux raccourcis natifs qui
-- contourneraient nos règles -- demandé explicitement par l'utilisateur (23/10/2026) : « réparer la voiture »
-- (touche Insert par défaut) et « apparaître une voiture à sa guise » (sélecteur de véhicule natif).
--
-- Vraie API publique du jeu trouvée en lisant les sources (BeamNG installé sur cette machine,
-- lua/ge/extensions/core/input/actionFilter.lua) : core_input_actionFilter.addAction(filter, groupeOuAction,
-- bloqué) -- le mécanisme OFFICIEL du jeu pour désactiver des actions (déjà utilisé par le jeu lui-même pour
-- les modes compétitifs/cinématiques), avec des groupes déjà définis exactement pour ce qu'on veut :
--   * vehicleRecovery = {"recover_vehicle", "recover_vehicle_alt", "recover_to_last_road"} -- la
--     réparation/récupération gratuite (Insert par défaut), cohérent avec la Phase 3/M (réparation payante).
--   * vehicleMenues = {"vehicle_selector", "parts_selector", "vehicledebugMenu"} -- le sélecteur de véhicule
--     natif (en tension directe avec « on ne peut faire apparaître que les véhicules qu'on possède »), plus le
--     configurateur de pièces natif (déjà bloqué côté API par computer.lua/Phase B -- ceci bloque aussi le
--     raccourci clavier qui y mène, en plus de l'appel lui-même).
-- Hors ligne (carrière solo, etc.), rien n'est bloqué : clear() dès qu'on quitte le serveur.
local M = {}

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

local FILTER = 'grnfr'
local GROUPS = { 'vehicleRecovery', 'vehicleMenues' }
local applied = false

local function lockActive()
  local o = rawget(_G, 'grnfr_online')
  local gh = rawget(_G, 'grnfr_ghosts')
  return o and o.isAuthed and o.isAuthed() and gh and gh.status and gh.status().joined == true
end

function M.update()
  local af = rawget(_G, 'core_input_actionFilter')
  if not af or type(af.addAction) ~= 'function' then return end
  local active = lockActive()
  if active and not applied then
    local ok = pcall(function()
      for _, g in ipairs(GROUPS) do af.addAction(FILTER, g, true) end
    end)
    if ok then
      applied = true
      slog('info', 'Input: blocked native vehicle recovery/selector actions while online.')
    end
  elseif not active and applied then
    pcall(af.clear, FILTER)
    applied = false
    slog('info', 'Input: native vehicle recovery/selector actions unblocked (offline).')
  end
end

return M
