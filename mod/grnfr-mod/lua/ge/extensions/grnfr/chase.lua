-- Configuration de jeu « Chase » (EN DÉVELOPPEMENT, jeu libre). Deux rôles :
--   'flee'   : le joueur fuit. Une voiture de police IA (puissance proche de celle du joueur) apparaît à côté et le poursuit.
--   'pursue' : le joueur EST la police. Un suspect IA, de même puissance que la voiture du joueur, apparaît devant lui et s'enfuit.
-- Dans les deux cas : le jeu est mis en pause, un compte à rebours 3-2-1-TOP s'affiche (UI), les deux voitures restent
-- immobiles, puis au TOP le jeu reprend et l'IA démarre. Aucune touche à presser.
-- Les API utilisées (core_vehicles.getConfigList / spawnNewVehicle, simTimeAuthority, ai.setMode('chase')...)
-- sont des hypothèses non vérifiées en jeu ; chaque appel est protégé par pcall.
local M = {}
local phase = 'idle' -- idle | countdown (jeu en pause, 3-2-1) | running
local role = 'flee' -- flee : le joueur fuit la police IA | pursue : le joueur est la police et poursuit un suspect IA
local aiId, startPos, startRot = nil, nil, nil
local cd, cdTimer, lastClock = 0, 0, os.clock() -- chiffre affiché (3, 2, 1), temps écoulé sur ce chiffre (s), horloge de secours
local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

local function toast(msg, kind)
  pcall(function() guihooks.trigger('toastrMsg', { type = kind or 'info', title = 'GRNFR Chase', msg = msg, config = { timeOut = 9000 } }) end)
end
-- Annonce un chiffre du compte à rebours à l'UI (v = 3, 2, 1, puis 0 = TOP) et joue le son du jeu si disponible.
local SOUNDS = { [3] = 'UI_Countdown1', [2] = 'UI_Countdown2', [1] = 'UI_Countdown3', [0] = 'UI_CountdownGo' }
local function fire(v)
  pcall(function() guihooks.trigger('GRNFRChaseCount', { value = v, role = role }) end)
  pcall(function() Engine.Audio.playOnce('AudioGui', 'event:' .. SOUNDS[v]) end)
end
local function setPause(p) pcall(function() simTimeAuthority.pause(p) end) end
local function isPaused()
  local ok, r = pcall(function() return simTimeAuthority.getPause() end)
  return ok and r == true
end
local function playerVeh() local ok, v = pcall(function() return be:getPlayerVehicle(0) end) if ok then return v end end
local function lang() local ok, l = pcall(function() return grnfr_settings.get().lang end) return ok and l or 'fr' end
local function L(fr, en) return lang() == 'en' and en or fr end

local function configs()
  local ok, l = pcall(function() return core_vehicles.getConfigList() end)
  if ok and type(l) == 'table' then return l.configs or l end
end
local function toNum(x)
  if type(x) == 'table' then x = x.max or x.value or x[1] end
  return tonumber(x)
end
local function perfOf(c)
  local p = toNum(c.Power) or toNum(c.aggregates and c.aggregates.Power)
  local w = toNum(c.Weight) or toNum(c.aggregates and c.aggregates.Weight)
  if p and w and w > 0 then return p / w * 1000 end -- ch par tonne
  return p
end

-- Modèle et configuration de la voiture du joueur (nil si inconnus)
local function playerCfg()
  local veh = playerVeh()
  if not veh then return nil end
  local ok, model, cfg = pcall(function()
    local pc = tostring(veh.partConfig or '')
    return veh.jbeam, pc:match('([^/\\]+)%.pc$')
  end)
  if ok and model and cfg then return model, cfg end
end

local function playerPerf(list)
  local model, cfg = playerCfg()
  if not (model and cfg and list) then return nil end
  for _, c in pairs(list) do
    if type(c) == 'table' and c.model_key == model and (c.config_key == cfg or c.key == cfg) then return perfOf(c) end
  end
end

-- Choisit la config de police dont la puissance est la plus proche d'un peu plus que celle du joueur.
local function pickPolice()
  local list = configs()
  local police = {}
  if list then
    for _, c in pairs(list) do
      if type(c) == 'table' and c.model_key then
        local key = tostring(c.config_key or c.key or ''):lower()
        local name = tostring(c.Name or c.name or ''):lower()
        if key:find('police') or name:find('police') then police[#police + 1] = c end
      end
    end
  end
  if #police == 0 then return { model_key = 'fullsize', config_key = 'police' } end -- repli (hypothèse)
  table.sort(police, function(a, b) return tostring(a.key or a.config_key) < tostring(b.key or b.config_key) end)
  local pp = playerPerf(list)
  if not pp then return police[math.ceil(#police / 2)] end
  local best, bestD
  for _, c in ipairs(police) do
    local s = perfOf(c)
    if s then
      local d = math.abs(s - pp * 1.1)
      if not bestD or d < bestD then best, bestD = c, d end
    end
  end
  return best or police[1]
end

-- Rôle « police » : choisit le suspect parmi les voitures (hors police/remorques) dont la puissance est la plus proche
-- de celle du joueur, en évitant sa propre configuration. Si la puissance du joueur est inconnue (véhicule moddé...),
-- le suspect est un clone de la voiture du joueur : performances identiques par construction.
local function pickSuspect()
  local list = configs()
  local pm, pc = playerCfg()
  local pp = playerPerf(list)
  local cands = {}
  if list and pp then
    for _, c in pairs(list) do
      if type(c) == 'table' and c.model_key and perfOf(c) then
        local key = tostring(c.config_key or c.key or ''):lower()
        local name = tostring(c.Name or c.name or ''):lower()
        local t = c.Type or (c.aggregates and c.aggregates.Type)
        local isCar = true
        if type(t) == 'string' then isCar = (t == 'Car') elseif type(t) == 'table' then isCar = (t.Car ~= nil) end
        local own = (c.model_key == pm and (c.config_key == pc or c.key == pc))
        local bad = key:find('police') or name:find('police') or key:find('trailer') or name:find('trailer') or key:find('prop')
        if isCar and not own and not bad then cands[#cands + 1] = c end
      end
    end
  end
  if #cands > 0 then
    table.sort(cands, function(a, b) return math.abs(perfOf(a) - pp) < math.abs(perfOf(b) - pp) end)
    local n = math.min(3, #cands) -- un peu de variété parmi les 3 plus proches
    return cands[math.random(n)], false
  end
  if pm and pc then return { model_key = pm, config_key = pc }, true end
  return nil
end

local function deleteAi()
  if aiId then
    pcall(function() local o = be:getObjectByID(aiId) if o then o:delete() end end)
    aiId = nil
  end
end

local function sendChase()
  local veh, pv = aiId and be:getObjectByID(aiId), playerVeh()
  if veh and pv then
    pcall(function()
      if role == 'pursue' then -- le suspect fuit la voiture du joueur
        veh:queueLuaCommand(string.format("ai.setMode('flee') ai.setTargetObjectID(%d) ai.setAggression(0.9)", pv:getID()))
      else -- la police poursuit le joueur
        veh:queueLuaCommand(string.format("ai.setMode('chase') ai.setTargetObjectID(%d) ai.setAggression(0.95) pcall(function() electrics.set_lightbar_signal(2) end)", pv:getID()))
      end
    end)
  end
end

local function spawnAi()
  local pv = playerVeh()
  if not pv then return false end
  local c, cloned
  if role == 'pursue' then c, cloned = pickSuspect() else c = pickPolice() end
  if not c then slog('problem', 'Chase: no suitable suspect car was found.'); return false end
  local ok, obj = pcall(function()
    local pos, dir, up = pv:getPosition(), pv:getDirectionVector(), pv:getDirectionVectorUp()
    local right = dir:cross(up):normalized()
    local spawnPos
    if role == 'pursue' then spawnPos = pos + dir * 14 -- le suspect démarre devant la voiture du joueur
    else spawnPos = pos + right * 4.5 - dir * 1 end -- la police démarre à côté
    local rot = quatFromDir(dir, up)
    return core_vehicles.spawnNewVehicle(c.model_key, { config = c.config_key or c.key, pos = spawnPos, rot = rot, autoEnterVehicle = false })
  end)
  if not ok or not obj then
    slog('problem', role == 'pursue' and 'Chase: the suspect car could not be spawned (the game refused it).' or 'Police chase: the police car could not be spawned (the game refused it).')
    return false
  end
  aiId = type(obj) == 'number' and obj or obj:getID()
  local what = tostring(c.model_key) .. ' / ' .. tostring(c.config_key or c.key)
  if role == 'pursue' then
    slog('info', 'Chase (you are the police): suspect car spawned (' .. what .. ')' .. (cloned and ', a copy of your own car because its power could not be compared.' or ', similar power to your car.'))
  else
    slog('info', 'Police chase: police car spawned (' .. what .. ').')
  end
  return true -- les ordres de l'IA ne sont envoyés qu'au TOP (sendChase dans finishCountdown)
end

-- Lance (ou relance) le compte à rebours : jeu en pause, voitures immobiles, l'UI affiche 3-2-1-TOP.
local function beginCountdown()
  phase, cd, cdTimer, lastClock = 'countdown', 3, 0, os.clock()
  fire(3)
end

-- TOP : le jeu reprend et l'IA démarre en même temps (les deux voitures bougent à partir de cet instant).
local function finishCountdown()
  cd = 0
  setPause(false)
  sendChase()
  phase = 'running'
  fire(0)
  slog('info', 'Chase: GO! The countdown is over and the chase is running.')
end

-- r = 'pursue' : le joueur est la police ; sinon (défaut) : le joueur fuit la police IA.
function M.start(r)
  role = (r == 'pursue') and 'pursue' or 'flee'
  local pv = playerVeh()
  if not pv then
    slog('warn', 'Chase was not started: you are not driving any vehicle.')
    toast(L('Aucune voiture pour le chase.', 'No vehicle for the chase.'), 'warning')
    return false
  end
  deleteAi()
  startPos, startRot = pv:getPosition(), quatFromDir(pv:getDirectionVector(), pv:getDirectionVectorUp())
  setPause(true)
  if not spawnAi() then
    setPause(false)
    phase = 'idle'
    toast(L('Impossible de faire apparaître la voiture du chase (voir le journal de session).', 'Could not spawn the chase car (see the session log).'), 'error')
    return false
  end
  slog('info', 'Chase started (' .. (role == 'pursue' and 'you are the police' or 'the police chase you') .. '). Countdown 3-2-1: the cars stay still until GO.')
  beginCountdown()
  return true
end

function M.restart()
  local pv = playerVeh()
  if phase == 'idle' or not pv then return M.start(role) end
  deleteAi()
  setPause(true)
  pcall(function()
    pv:requestReset(RESET_PHYSICS)
    if startPos and startRot then pv:setPositionRotation(startPos.x, startPos.y, startPos.z, startRot.x, startRot.y, startRot.z, startRot.w) end
  end)
  slog('info', 'Chase restarted: your car was put back at the start position. Countdown 3-2-1.')
  if not spawnAi() then
    setPause(false)
    phase = 'idle'
    return false
  end
  beginCountdown()
end

-- Touche J / action « go » : saute le compte à rebours.
function M.go()
  if phase ~= 'countdown' then return end
  finishCountdown()
end

function M.stop()
  if phase == 'idle' then return end
  slog('info', 'Chase stopped. The AI car was removed.')
  deleteAi()
  if isPaused() then setPause(false) end
  phase, cd = 'idle', 0
end

function M.update(dt)
  if phase ~= 'countdown' then lastClock = os.clock() return end
  -- durée réelle de l'image : dt du jeu, ou horloge de secours si dt est absent/aberrant pendant la pause
  local c = os.clock()
  local d = tonumber(dt) or 0
  if d <= 0 or d > 0.5 then d = math.min(math.max(c - lastClock, 0), 0.1) end
  lastClock = c
  if not isPaused() then setPause(true) end -- les voitures ne bougent pas avant le TOP, même si le joueur touche à la pause
  cdTimer = cdTimer + d
  if cdTimer >= 1 then
    cdTimer = cdTimer - 1
    cd = cd - 1
    if cd > 0 then fire(cd) else finishCountdown() end
  end
end

function M.status() return { phase = phase, role = role, count = cd } end
return M
