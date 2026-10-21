-- Raccourci : l'action "grnfr_toggle" est déclarée dans lua/ge/extensions/core/input/actions/grnfr.json.
-- La touche PAR DÉFAUT (K, libre dans BeamNG) est livrée par le mod dans settings/inputmaps/keyboardGRNFR.json
-- (mécanisme documenté : nom de fichier = périphérique + suffixe libre). Le joueur peut la changer dans
-- Options > Contrôles > « GRNFR Mod » ; ce module lit (lecture seule) la touche réellement assignée.
local M = {}
M.ACTION = 'grnfr_toggle'
M.DEFAULT = 'K'

function M.getLabel()
  local ok, label = pcall(function()
    local devs = core_input_bindings and core_input_bindings.bindings
    if type(devs) ~= 'table' then return nil end
    for _, dev in pairs(devs) do
      local list = dev.contents and dev.contents.bindings
      if type(list) == 'table' then
        for _, b in pairs(list) do
          if b.action == M.ACTION and b.control then return tostring(b.control):upper() end
        end
      end
    end
  end)
  if ok and label then return label end
  return nil -- aucune assignation lue
end

-- Touche à afficher : celle lue, sinon la touche par défaut livrée avec le mod.
function M.getDisplay()
  return M.getLabel() or M.DEFAULT
end

return M
