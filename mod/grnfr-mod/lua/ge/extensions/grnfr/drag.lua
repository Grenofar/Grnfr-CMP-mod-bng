-- GRNFR Online : courses de drag organisées entre joueurs du même serveur, avec mise d'argent (voir
-- supabase/migrations/0007_drag_races.sql). Déroulement : un joueur marque un départ et une arrivée et
-- propose la course -> phase de mises -> l'hôte lance -> compte à rebours 3-2-1-TOP (voiture bloquée frein de
-- parking + embrayage jusqu'au TOP : pas de faux départ) -> chacun signale son temps en franchissant
-- l'arrivée -> le plus rapide empoche tout le pot.
--
-- IMPORTANT (honnêteté) : bloquer une "vraie" launch control (RPM tenu, embrayage qui claque au TOP) dépend
-- du véhicule et n'est pas une API fiable à deviner sans jeu pour tester. Ce module bloque donc TOUS les
-- véhicules de la même façon, qu'ils aient une launch control ou non : frein de parking + embrayage à fond en
-- écrasant l'entrée (`input.event`, hypothèse non vérifiée comme le reste du mod), relâchés au TOP.
local M = {}

local race = nil        -- dernier état reçu de get_drag_race()
local joined = false
local pollAcc = 0
local POLL = 1

local pendingStart, pendingFinish = nil, nil -- points marqués, avant la proposition

-- Compte à rebours local (uniquement si je participe à la course et qu'elle vient de démarrer)
local phase = 'idle'    -- idle | countdown | running | done
local cd, cdTimer = 0, 0
local lockId = nil      -- id du véhicule actuellement bloqué (relâché si on change de voiture)
local raceStartClock = nil
local reportedForRace = nil
local clock = 0

local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local function lang() local ok, l = pcall(function() return grnfr_settings.get().lang end) return ok and l or 'fr' end
local function L(fr, en) return lang() == 'en' and en or fr end
local function playerVeh() local ok, v = pcall(function() return be:getPlayerVehicle(0) end) if ok then return v end end
local function toast(msg, kind) pcall(function() guihooks.trigger('toastrMsg', { type = kind or 'info', title = 'GRNFR Drag', msg = msg, config = { timeOut = 7000 } }) end) end

function M.setServer(isJoined)
  joined = isJoined == true
  if not joined then M.reset() end
end

-- ------------------------------------------------------------------ préparer / proposer
function M.markStart()
  local p = grnfr_places.playerPos()
  if not p then return false end
  pendingStart = { x = p.x, y = p.y, z = p.z }
  toast(L('Départ marqué ici.', 'Start marked here.'))
  return true
end

function M.markFinish()
  local p = grnfr_places.playerPos()
  if not p then return false end
  pendingFinish = { x = p.x, y = p.y, z = p.z }
  toast(L('Arrivée marquée ici.', 'Finish marked here.'))
  return true
end

function M.propose()
  if not pendingStart or not pendingFinish then
    toast(L('Marquez un départ et une arrivée avant de proposer une course.', 'Mark a start and a finish before proposing a race.'), 'warning')
    return
  end
  grnfr_online.call('propose_drag_race', { p_level = grnfr_places.level(), p_start = pendingStart, p_finish = pendingFinish }, function(ok, err)
    if ok then pendingStart, pendingFinish = nil, nil; M.poll()
    else toast(grnfr_online.errText(err), 'error') end
  end)
end

function M.join(stake)
  local n = tonumber(stake)
  if not n or n <= 0 then return end
  grnfr_online.call('join_drag_race', { p_race = race and race.id, p_stake = math.floor(n) }, function(ok, err)
    if ok then M.poll() else toast(grnfr_online.errText(err), 'error') end
  end)
end

function M.leave()
  if not race then return end
  grnfr_online.call('leave_drag_race', { p_race = race.id }, function(ok, err)
    if ok then M.poll() else toast(grnfr_online.errText(err), 'error') end
  end)
end

function M.start()
  if not race then return end
  grnfr_online.call('start_drag_race', { p_race = race.id }, function(ok, err)
    if not ok then toast(grnfr_online.errText(err), 'error') end
  end)
end

function M.forceFinish()
  if not race then return end
  grnfr_online.call('force_finish_drag_race', { p_race = race.id }, function(ok, err)
    if not ok then toast(grnfr_online.errText(err), 'error') end
  end)
end

-- ------------------------------------------------------------------ blocage anti faux départ
local function setLock(on)
  local v = playerVeh()
  if not v then return end
  local ok = pcall(function()
    local id = v:getID()
    lockId = on and id or nil
    v:queueLuaCommand(string.format(
      "if input and input.event then input.event('parkingbrake', %d, 'FILTER_DIRECT') input.event('clutch', %d, 'FILTER_DIRECT') end",
      on and 1 or 0, on and 1 or 0))
  end)
  if not ok then lockId = nil end
end

local SOUNDS = { [3] = 'UI_Countdown1', [2] = 'UI_Countdown2', [1] = 'UI_Countdown3', [0] = 'UI_CountdownGo' }
local function fireCount(v)
  pcall(function() guihooks.trigger('GRNFRDragCount', { value = v }) end)
  pcall(function() Engine.Audio.playOnce('AudioGui', 'event:' .. SOUNDS[v]) end)
end

local function beginCountdown()
  phase, cd, cdTimer = 'countdown', 3, 0
  setLock(true)
  fireCount(3)
  slog('info', 'Drag race: countdown started, car locked (parking brake + clutch) until GO.')
end

local function finishCountdown()
  setLock(false)
  phase = 'running'
  raceStartClock = clock
  fireCount(0)
  slog('info', 'Drag race: GO!')
end

local FINISH_RADIUS = 15 -- m
local function checkFinishLine()
  if phase ~= 'running' or not race or not race.finish_pos then return end
  if reportedForRace == race.id then return end
  local p = grnfr_places.playerPos()
  if not p then return end
  if grnfr_places.dist(race.finish_pos, p) <= FINISH_RADIUS then
    reportedForRace = race.id
    local ms = math.floor(((clock - (raceStartClock or clock))) * 1000)
    grnfr_online.call('report_drag_finish', { p_race = race.id, p_ms = ms }, function(ok, err)
      if ok then toast(L('Arrivée enregistrée !', 'Finish recorded!'))
      else toast(grnfr_online.errText(err), 'error'); reportedForRace = nil end
    end)
  end
end

-- ------------------------------------------------------------------ état (sondage régulier)
local function amIEntered()
  if not race or not race.entries then return false end
  for _, e in ipairs(race.entries) do if e.mine then return true end end
  return false
end

function M.poll()
  if not joined then return end
  grnfr_online.call('get_drag_race', {}, function(ok, data)
    if not ok then return end
    local prevStatus = race and race.status or nil
    race = (type(data) == 'table') and data or nil
    if race and race.status == 'running' and prevStatus ~= 'running' and amIEntered() and phase == 'idle' then
      beginCountdown()
    elseif (not race or race.status ~= 'running') and phase ~= 'idle' and phase ~= 'done' then
      -- la course s'est terminée/annulée pendant que je courais : on débloque et on arrête de chercher la ligne
      setLock(false)
      phase = (race and race.status == 'finished') and 'done' or 'idle'
    end
    if not race then reportedForRace = nil; phase = 'idle' end
  end)
end

function M.update(dt)
  clock = clock + dt
  if not joined then return end
  pollAcc = pollAcc + dt
  if pollAcc >= POLL then pollAcc = 0; M.poll() end
  if phase == 'countdown' then
    setLock(true) -- réaffirme le blocage à chaque image (l'entrée écrasée ne dure qu'une image)
    cdTimer = cdTimer + dt
    if cdTimer >= 1 then
      cdTimer = cdTimer - 1
      cd = cd - 1
      if cd > 0 then fireCount(cd) else finishCountdown() end
    end
  elseif phase == 'running' then
    checkFinishLine()
  end
end

function M.status()
  return {
    race = race, phase = phase, hasStart = pendingStart ~= nil, hasFinish = pendingFinish ~= nil,
  }
end

function M.reset()
  if lockId then setLock(false) end
  race, pendingStart, pendingFinish = nil, nil, nil
  phase, cd, cdTimer, raceStartClock, reportedForRace = 'idle', 0, 0, nil, nil
end

return M
