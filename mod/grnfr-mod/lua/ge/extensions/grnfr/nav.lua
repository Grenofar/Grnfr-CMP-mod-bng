-- GRNFR Online : destination en cours (balise dessinée dans le monde + guidage du jeu si disponible) et mesures du joueur.
local M = {}
local target = nil -- { x, y, z, label, radius }

local function playerVeh() local ok, v = pcall(function() return be:getPlayerVehicle(0) end) if ok then return v end end

function M.playerPos()
  local v = playerVeh()
  if not v then return nil end
  local ok, p = pcall(function() return v:getPosition() end)
  if ok then return p end
end

function M.playerSpeed()
  local v = playerVeh()
  if not v then return 0 end
  local ok, s = pcall(function() return v:getVelocity():length() end)
  return ok and tonumber(s) or 0
end

local function setGps(pos)
  -- guidage du jeu (ligne verte au sol) : API non vérifiée, essayée sans insister
  pcall(function()
    if core_groundMarkers and core_groundMarkers.setPath then core_groundMarkers.setPath(pos)
    elseif core_groundMarkers and core_groundMarkers.setFocus then core_groundMarkers.setFocus(pos) end
  end)
end

function M.set(x, y, z, label, radius)
  target = { x = x, y = y, z = z or 0, label = label or '', radius = radius or 30 }
  setGps(vec3(x, y, z or 0))
end

function M.clear()
  if target then pcall(function() if core_groundMarkers and core_groundMarkers.setPath then core_groundMarkers.setPath(nil) end end) end
  target = nil
end

function M.get() return target end

function M.distance()
  local p, t = M.playerPos(), target
  if not (p and t) then return nil end
  local dx, dy = p.x - t.x, p.y - t.y
  return math.sqrt(dx * dx + dy * dy)
end

-- Arrivé : à moins de `radius` mètres et quasi à l'arrêt.
function M.arrived(maxSpeed)
  local d = M.distance()
  return d ~= nil and d <= target.radius and M.playerSpeed() <= (maxSpeed or 4)
end

-- Balise : sphère + colonne de lumière + texte au-dessus de la destination (à appeler à chaque image).
function M.update()
  if not target then return end
  pcall(function()
    local p = vec3(target.x, target.y, target.z)
    local c = ColorF(1, 0.4, 0, 0.9)
    debugDrawer:drawSphere(p, 2.5, c)
    debugDrawer:drawLine(p, p + vec3(0, 0, 80), c)
    if target.label ~= '' then debugDrawer:drawText(p + vec3(0, 0, 84), String(target.label), ColorF(1, 1, 1, 1)) end
  end)
end

return M
