-- GRNFR Online : envoie UNE fois le réseau routier de la carte (vu de dessus) au serveur, pour la carte en direct de
-- l'app GRNFR Host CMP (supabase/migrations/0013_live_map.sql). Seulement des segments 2D [x1, y1, x2, y2] en
-- mètres, lus dans le graphe de navigation du jeu (map.getMap().nodes : API non vérifiée, sous pcall).
-- On demande d'abord au serveur s'il en a besoin (level_roads_needed) : la plupart du temps, rien n'est envoyé.
local M = {}

local joined = false
local doneLevel = nil   -- carte déjà traitée (envoyée, ou le serveur l'avait déjà)
local busy = false
local wait = 0
local MAX_SEGMENTS = 60000

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

function M.setServer(isJoined) joined = isJoined == true end

-- Segments uniques (a-b et b-a ne comptent qu'une fois), arrondis au mètre.
function M.buildSegments()
  local segs = {}
  pcall(function()
    local nodes = map.getMap().nodes
    local seen = {}
    for id, n in pairs(nodes) do
      if n.pos and n.links then
        for other in pairs(n.links) do
          local o = nodes[other]
          if o and o.pos then
            local a, b = tostring(id), tostring(other)
            local key = a < b and (a .. '|' .. b) or (b .. '|' .. a)
            if not seen[key] then
              seen[key] = true
              segs[#segs + 1] = { math.floor(n.pos.x + 0.5), math.floor(n.pos.y + 0.5), math.floor(o.pos.x + 0.5), math.floor(o.pos.y + 0.5) }
              if #segs >= MAX_SEGMENTS then error('enough') end
            end
          end
        end
      end
    end
  end)
  return segs
end

function M.update(dt)
  if not joined or busy then return end
  local level = grnfr_places.level()
  if level == 'unknown' or level == doneLevel then return end
  wait = wait + dt
  if wait < 10 then return end -- laisse la carte et sa navigation se charger
  wait = 0
  busy = true
  grnfr_online.call('level_roads_needed', { p_level = level }, function(ok, needed)
    if not ok then busy = false return end -- on retentera plus tard
    if needed ~= true then doneLevel, busy = level, false return end
    local segs = M.buildSegments()
    if #segs < 10 then doneLevel, busy = level, false; slog('warn', 'Live map: no road network found on this map.') return end
    grnfr_online.call('upload_level_roads', { p_level = level, p_roads = segs }, function(ok2)
      busy = false
      if ok2 then doneLevel = level; slog('info', 'Live map: sent the road network of ' .. level .. ' (' .. #segs .. ' segments).') end
    end)
  end)
end

function M.reset() busy, wait = false, 0 end

return M
