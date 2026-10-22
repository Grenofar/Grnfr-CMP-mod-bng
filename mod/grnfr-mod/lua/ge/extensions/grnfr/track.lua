-- GRNFR Online : repère un joueur choisi depuis le téléphone (touche K). Dessine un point qui suit sa
-- position, mise à jour à chaque fois que la liste des joueurs du serveur est reçue (~2-3 fois/s, largement
-- suffisant pour l'usage demandé : « le point bouge avec la personne toutes les 2 s »). Indépendant de
-- grnfr_nav (destinations de taxi) : les deux peuvent être actifs en même temps sans se gêner.
local M = {}

local trackedName = nil
local pos = nil -- dernière position connue du joueur suivi

function M.set(name) trackedName = (type(name) == 'string' and name ~= '') and name or nil; pos = nil end
function M.clear() trackedName, pos = nil, nil end
function M.get() return trackedName end

-- Appelé par ghosts.lua à chaque réception de la liste des joueurs du serveur.
function M.onPlayers(players)
  if not trackedName or type(players) ~= 'table' then return end
  for _, p in ipairs(players) do
    if p.username == trackedName and type(p.pos) == 'table' then
      pos = { x = p.pos.x, y = p.pos.y, z = p.pos.z }
      return
    end
  end
end

function M.update()
  if not trackedName or not pos then return end
  pcall(function()
    local p = vec3(pos.x, pos.y, pos.z)
    local c = ColorF(0.25, 0.6, 1, 0.9)
    debugDrawer:drawSphere(p, 1.6, c)
    debugDrawer:drawLine(p, p + vec3(0, 0, 60), c)
    debugDrawer:drawText(p + vec3(0, 0, 64), String(trackedName), ColorF(1, 1, 1, 1))
  end)
end

function M.status() return { name = trackedName } end

function M.reset() trackedName, pos = nil, nil end

return M
