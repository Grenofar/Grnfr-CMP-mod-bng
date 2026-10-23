-- GRNFR Online : radars de vitesse + caméras de feu rouge (grand chantier Phase I, 22-23/10/2026).
--
-- Demande précisée par l'utilisateur : « le radar n'est pas dans la voiture » (pas un contrôle permanent) —
-- « mets-en pas partout » — « quand il passe à proximité il en tire la vitesse et c'est une amende ou pas ».
-- Implémenté avec les VRAIS radars/caméras du jeu : des déclencheurs réels (BeamNGTrigger, speedTrapType =
-- "speed" ou "redLight") que le jeu place lui-même à des endroits précis de certaines cartes (pas partout, pas
-- inventé par nous) — voir lua/ge/extensions/gameplay/speedTraps.lua dans les fichiers du jeu. Le jeu calcule
-- déjà tout seul si la voiture roulait trop vite (et dans le bon sens) ou si le feu était réellement rouge
-- (core_trafficSignals), et déclenche alors un hook (extensions.hook) : onSpeedTrapTriggered / onRedLightCamTriggered.
-- Ce module écoute ces deux hooks (mécanisme standard d'extension du jeu : n'importe quelle extension chargée qui
-- définit une fonction du même nom la reçoit automatiquement, comme onClientStartMission) et demande une amende
-- au serveur -- qui DÉCIDE SEUL du montant (jamais le client). La vitesse/limite rapportées ne servent qu'à
-- l'affichage ; le serveur les plafonne par sécurité, mais rien n'empêche un client de ne jamais appeler ces
-- fonctions : comme le reste de l'anti-triche du projet, c'est volontairement « limité, pas infaillible ».
local M = {}

local function online() return rawget(_G, 'grnfr_online') end
local function L(fr, en) local o = online() return o and o.L(fr, en) or fr end
local function toast(m, k) local o = online() if o then o.toast(m, k) end end
local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local function fmtMoney(n) return '$' .. tostring(math.floor(tonumber(n) or 0)) end

-- Appelé par le jeu (extensions.hook('onSpeedTrapTriggered', data, vehSpeed, overSpeed)) uniquement quand la
-- vitesse mesurée dépasse déjà la limite dans le bon sens -- voir speedTraps.lua. vehSpeed est en m/s.
function M.onSpeedTrapTriggered(data, vehSpeed)
  local o = online()
  if not (o and o.isAuthed()) then return end -- hors ligne GRNFR : pas d'amende
  local limitKmh = (tonumber(data and data.speedLimit) or 0) * 3.6
  local speedKmh = (tonumber(vehSpeed) or 0) * 3.6
  o.call('report_speeding', { p_speed_kmh = speedKmh, p_limit_kmh = limitKmh }, function(ok, res)
    if not ok or type(res) ~= 'table' then return end
    local fine = tonumber(res.fine) or 0
    if fine > 0 then
      toast(L('Radar : excès de vitesse (', 'Speed camera: speeding (') .. math.floor(speedKmh + 0.5) .. L(' km/h, limite ', ' km/h, limit ')
        .. math.floor(limitKmh + 0.5) .. L(') : amende de ', '): fine of ') .. fmtMoney(fine), 'warning')
      slog('warn', 'Radar: speeding fine ' .. fmtMoney(fine) .. ' (' .. math.floor(speedKmh) .. '/' .. math.floor(limitKmh) .. ' km/h).')
    end
  end)
end

-- Appelé par le jeu (extensions.hook('onRedLightCamTriggered', data, vehSpeed)) uniquement quand le feu était
-- réellement rouge au passage (déjà vérifié par core_trafficSignals côté jeu).
function M.onRedLightCamTriggered(data, vehSpeed)
  local o = online()
  if not (o and o.isAuthed()) then return end
  o.call('report_red_light', {}, function(ok, res)
    if not ok or type(res) ~= 'table' then return end
    local fine = tonumber(res.fine) or 0
    if fine > 0 then
      toast(L('Feu rouge brûlé : amende de ', 'Red light camera: fine of ') .. fmtMoney(fine), 'warning')
      slog('warn', 'Radar: red light fine ' .. fmtMoney(fine) .. '.')
    end
  end)
end

return M
