-- GRNFR Mod : extension GE principale (orchestration uniquement).
local M = {}
M.dependencies = { 'grnfr_sessionlog', 'grnfr_settings', 'grnfr_perf', 'grnfr_mode', 'grnfr_keys', 'grnfr_stutter', 'grnfr_traffic',
  'grnfr_places', 'grnfr_facilities', 'grnfr_nav', 'grnfr_http', 'grnfr_online', 'grnfr_taxi', 'grnfr_taxibot', 'grnfr_bus', 'grnfr_ghosts', 'grnfr_garage', 'grnfr_convoy',
  'grnfr_chat', 'grnfr_track', 'grnfr_drag', 'grnfr_profile', 'grnfr_travel', 'grnfr_roadmap' }

local VERSION = '2.4.1'
local uiAttached = false
local consumers = {} -- UI abonnées (angular, panel, overlay) : on ne pousse des données que si au moins une est ouverte
local hudOpen = false
local bigOpen = false -- grande fenêtre en jeu (bouton Option du HUD)
local onlineOpen = false -- fenêtre GRNFR Online (touche O)
local quickOpen = false -- petite fenêtre rapide : chat, joueurs, drag (touche J)
local tabletOpen = false -- tablette du garage (touche O devant SON garage)
local acc = 0
local cntPre, cntUpd, cntPoll, cntSent = 0, 0, 0, 0 -- compteurs de diagnostic (log toutes les 5 s + affichés dans le HUD)
local modeInfo = { id = 'menu', label = 'Menu principal', session = false }
local lastSig = ''
local notified, notifyAcc = false, 0
local modeAcc = 0
local staticAcc = 0 -- secondes depuis le dernier envoi de l'état à l'UI (renvoi de sécurité chaque seconde)
local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end
local wasSession, lastModeEn = false, nil
local sessionAge = 0 -- secondes écoulées depuis le début de la partie (sert à réarmer le trafic adaptatif)

local MODE_LABELS = {
  menu = { 'Menu principal', 'Main menu' }, career = { 'Carrière', 'Career' },
  freeroam = { 'Jeu libre', 'Free roam' }, scenario = { 'Scénario', 'Scenario' },
  garage = { 'Garage', 'Garage' }, bus = { 'Bus', 'Bus' }, rally = { 'Rallye', 'Rally' },
  multiplayer = { 'Multijoueur', 'Multiplayer' }, localmp = { 'Multijoueur local', 'Local multiplayer' },
  startexp = { 'Expérience de démarrage', 'Starting experience' },
  session = { 'Session active (mode inconnu)', 'Active session (unknown mode)' },
}
local function L(fr, en) return (grnfr_settings.get().lang == 'en') and en or fr end
local function modeLabel()
  local parts = {}
  for _, id in ipairs(modeInfo.ids or {}) do
    local m = MODE_LABELS[id]
    parts[#parts + 1] = m and L(m[1], m[2]) or (modeInfo.raw or id)
  end
  if #parts == 0 then return modeInfo.label end
  return table.concat(parts, ' · ')
end

local function modeLabelEn()
  local parts = {}
  for _, id in ipairs(modeInfo.ids or {}) do
    local m = MODE_LABELS[id]
    parts[#parts + 1] = m and m[2] or (modeInfo.raw or id)
  end
  if #parts == 0 then return 'Unknown' end
  return table.concat(parts, ' + ')
end
local function levelName()
  local ok, n = pcall(function() return getMissionFilename() end)
  if ok and type(n) == 'string' then
    local lv = n:match('levels/([^/\\]+)')
    if lv then return lv end
  end
  return 'unknown'
end

-- Reads the game mode and keeps the session log in step: a session starts when a map is loaded, ends when it is left.
local function refreshMode()
  modeInfo = grnfr_mode.detect()
  if not modeInfo.session then hudOpen = false; bigOpen = false end
  if modeInfo.session and not wasSession then
    wasSession, lastModeEn = true, modeLabelEn()
    pcall(grnfr_sessionlog.begin, { mode = lastModeEn, map = levelName(), modVersion = VERSION,
      gameVersion = rawget(_G, 'beamng_versionb') or rawget(_G, 'beamng_version') })
    slog('info', 'Detection details: ' .. tostring(modeInfo.diag))
  elseif not modeInfo.session and wasSession then
    wasSession = false
    pcall(grnfr_sessionlog.finish, 'You left the map.')
  elseif wasSession then
    local m = modeLabelEn()
    if m ~= lastModeEn then
      slog('info', 'Game mode changed: ' .. lastModeEn .. ' -> ' .. m .. '.')
      slog('info', 'Detection details: ' .. tostring(modeInfo.diag))
      lastModeEn = m
    end
  end
end

-- GRNFR Online (comptes, serveurs, garage) : toujours accessible depuis le menu principal (choisir/rejoindre un
-- serveur avant même de charger une carte), et en jeu libre ou multijoueur BeamMP. Jamais dans la carrière /
-- les scénarios / missions du jeu.
local ONLINE_BLOCKING = { career = true, scenario = true, mission = true, bus = true, rally = true, garage = true }
local function isOnlineAllowed()
  if not modeInfo.session then return true end -- menu principal : aucune carte chargée, aucun mode à bloquer
  for _, id in ipairs(modeInfo.ids or {}) do if ONLINE_BLOCKING[id] then return false end end
  return true
end

-- État complet envoyé à l'UI : soit poussé (événement GRNFRStatic), soit renvoyé directement par getState/requestState.
local function buildStatic()
  return {
    version = VERSION,
    session = modeInfo.session,
    mode = modeLabel(),
    modeId = modeInfo.id,
    modeIds = modeInfo.ids,
    modeRaw = modeInfo.raw,
    onlineAllowed = isOnlineAllowed(),
    onlineOpen = onlineOpen,
    quickOpen = quickOpen,
    hudOpen = hudOpen,
    bigOpen = bigOpen,
    traffic = grnfr_traffic.status(),
    hooks = cntPre + cntUpd,
    angular = consumers.angular == true, -- app HUD AngularJS placée par le joueur : le HUD Vue s'efface alors
    keyLabel = grnfr_keys.getDisplay(),
    settings = grnfr_settings.get(),
  }
end
local function pushStatic(force) guihooks.trigger('GRNFRStatic', buildStatic()) end

-- Appelé par l'action clavier "grnfr_toggle" (système d'actions officiel).
local function toast(msg)
  pcall(function() guihooks.trigger('toastrMsg', { type = 'info', title = 'GRNFR CMP', msg = msg }) end)
end

function M.toggleHud()
  refreshMode()
  if not modeInfo.session then
    toast(L("Le HUD GRNFR s'ouvre uniquement en partie (une carte doit être chargée).", 'The GRNFR HUD only opens in-game (a map must be loaded).'))
    return
  end
  if not grnfr_settings.get().hudEnabled then
    slog('info', 'You pressed ' .. grnfr_keys.getDisplay() .. ' but the HUD is turned off in Settings.')
    toast(L('HUD désactivé : activez-le dans GRNFR CMP > Paramètres.', 'HUD disabled: enable it in GRNFR CMP > Settings.'))
    return
  end
  if bigOpen then -- la grande fenêtre est ouverte : K la ferme (et le petit HUD ne revient pas)
    bigOpen, hudOpen = false, false
    slog('info', 'You closed the big window (' .. grnfr_keys.getDisplay() .. ').')
  else
    hudOpen = not hudOpen
    slog('info', hudOpen and ('You opened the small HUD (' .. grnfr_keys.getDisplay() .. ').') or ('You closed the small HUD (' .. grnfr_keys.getDisplay() .. ').'))
  end
  pushStatic(true) -- envoyé même si aucune UI n'est encore abonnée (le HUD Vue s'abonne en recevant l'état)
end

-- ------------------------------------------------------------------ GRNFR Online
local function setOnlineOpen(on)
  on = on == true
  if on and not isOnlineAllowed() then
    refreshMode()
    if not isOnlineAllowed() then
      toast(L('GRNFR CMP : disponible en jeu libre ou en multijoueur (pas en carrière / scénario).', 'GRNFR CMP: available in free roam or multiplayer (not in career / scenario).'))
      return false
    end
  end
  onlineOpen = on
  grnfr_online.setFocus(on)
  if not on then grnfr_online.setTyping(false) end
  guihooks.trigger('GRNFROnlineWin', { open = onlineOpen })
  pushStatic(true)
  return true
end

-- Tablette du garage : seulement devant SON garage (garage.lua), en partie. Touche O : la tablette si on est devant
-- son garage, sinon la fenêtre GRNFR (compte, serveurs, réglages).
local function setTabletOpen(on)
  on = on == true
  if on and not (modeInfo.session and grnfr_garage.isNear()) then return false end
  if on and onlineOpen then setOnlineOpen(false) end
  tabletOpen = on
  grnfr_online.setFocus(on or onlineOpen or quickOpen)
  if not on and not onlineOpen and not quickOpen then grnfr_online.setTyping(false) end
  guihooks.trigger('GRNFRTabletWin', { open = tabletOpen, name = grnfr_garage.name() })
  return true
end
function M.toggleOnline()
  if tabletOpen then return setTabletOpen(false) end
  if not onlineOpen and modeInfo.session and grnfr_garage.isNear() then return setTabletOpen(true) end
  return setOnlineOpen(not onlineOpen)
end

-- Petite fenêtre rapide (touche J) : chat, liste des joueurs, repère, argent, échange, courses de drag.
-- Mêmes règles d'ouverture que GRNFR Online (jeu libre / multijoueur, pas en carrière / scénario).
local function setQuickOpen(on)
  on = on == true
  if on and not isOnlineAllowed() then
    refreshMode()
    if not isOnlineAllowed() then
      toast(L('Fenêtre rapide : disponible en jeu libre ou en multijoueur (pas en carrière / scénario).', 'Quick window: available in free roam or multiplayer (not in career / scenario).'))
      return false
    end
  end
  quickOpen = on
  grnfr_online.setFocus(on or onlineOpen or tabletOpen)
  if not on and not onlineOpen and not tabletOpen then grnfr_online.setTyping(false) end
  guihooks.trigger('GRNFRQuickWin', { open = quickOpen })
  pushStatic(true)
  return true
end
function M.toggleQuick() return setQuickOpen(not quickOpen) end

-- Appels de l'interface vers le jeu : un seul point d'entrée, liste blanche, arguments en JSON.
local ROUTES = {
  ['window.open']     = function() setOnlineOpen(true) end,
  ['window.close']    = function() setOnlineOpen(false) end,
  ['quick.open']      = function() setQuickOpen(true) end,
  ['tablet.close']    = function() setTabletOpen(false) end,
  ['quick.close']     = function() setQuickOpen(false) end,
  ['chat.send']       = function(a) grnfr_chat.send(a.text) end,
  ['track.set']       = function(a) grnfr_track.set(a.username) end,
  ['track.clear']     = function() grnfr_track.clear() end,
  ['drag.markStart']  = function() grnfr_drag.markStart() end,
  ['drag.markFinish'] = function() grnfr_drag.markFinish() end,
  ['drag.propose']    = function() grnfr_drag.propose() end,
  ['drag.join']       = function(a) grnfr_drag.join(a.stake) end,
  ['drag.leave']      = function() grnfr_drag.leave() end,
  ['drag.start']      = function() grnfr_drag.start() end,
  ['drag.forceFinish'] = function() grnfr_drag.forceFinish() end,
  ['profile.export']  = function(a)
    local ok, path = grnfr_profile.export(a)
    guihooks.trigger('GRNFRProfileExport', { ok = ok == true, path = path })
  end,
  ['profile.list']    = function() guihooks.trigger('GRNFRProfileList', { list = grnfr_profile.list() }) end,
  ['profile.import']  = function(a) guihooks.trigger('GRNFRProfileImport', { data = grnfr_profile.read(a.path) }) end,
  ['auth']            = function(a)
    grnfr_online.setAuth(a.loggedIn, a.username)
    if a.loggedIn ~= true then
      grnfr_ghosts.setServer(false); grnfr_convoy.setServer(false); grnfr_garage.setServer(false)
      grnfr_chat.setServer(false); grnfr_drag.setServer(false); grnfr_track.clear(); grnfr_roadmap.setServer(false)
    end
  end,
  ['server.state']    = function(a)
    grnfr_ghosts.setServer(a.joined, a.name, a.intervalMs); grnfr_convoy.setServer(a.joined); grnfr_garage.setServer(a.joined)
    grnfr_roadmap.setServer(a.joined)
    grnfr_chat.setServer(a.joined); grnfr_drag.setServer(a.joined)
    if not a.joined then grnfr_track.clear(); grnfr_travel.cancel() end
  end,
  ['server.arrive']   = function(a) grnfr_travel.arrive(a.vehicle) end,
  ['server.travel']   = function(a)
    grnfr_travel.go(a.level, a.pos, function() setOnlineOpen(false); setQuickOpen(false); setTabletOpen(false) end)
  end,
  ['typing']          = function(a) grnfr_online.setTyping(a.on) end,
  ['places.refresh']  = function() grnfr_online.requestPlaces() end,
  ['garage.spawn']    = function(a)
    if not grnfr_garage.isNear() then grnfr_online.toast(grnfr_online.L('Approchez-vous de votre garage.', 'Get closer to your garage.'), 'warning'); return end
    grnfr_online.spawnVehicle(a)
  end,
  ['garage.lock']     = function(a) grnfr_online.setLocked(a.id, a.on) end,
  ['garage.store']    = function(a)
    if not grnfr_garage.isNear() then grnfr_online.toast(grnfr_online.L('Approchez-vous de votre garage.', 'Get closer to your garage.'), 'warning'); return end
    grnfr_online.storeVehicle(a.id)
  end,
  ['taxi.duty']       = function(a) grnfr_taxi.setDuty(a.on) end,
  ['taxi.accept']     = function(a) grnfr_taxi.acceptRequest(a) end,
  ['taxi.cancel']     = function() grnfr_taxi.cancel() end,
  ['bot.call']        = function(a) grnfr_taxibot.call(a) end,
  ['bot.cancel']      = function() grnfr_taxibot.cancel() end,
  ['bus.start']       = function() grnfr_bus.start() end,
  ['bus.stop']        = function() grnfr_bus.stop() end,
  ['place.save']      = function(a) grnfr_places.addCurrent(a.name) end,
}
function M.ui(name, json)
  local f = ROUTES[tostring(name)]
  if not f then return false end
  local args = {}
  if type(json) == 'string' and json ~= '' then
    local ok, d = pcall(jsonDecode, json)
    if ok and type(d) == 'table' then args = d end
  end
  local ok, err = pcall(f, args)
  if not ok then slog('problem', 'Online action "' .. tostring(name) .. '" failed: ' .. tostring(err):sub(1, 120)) end
  return true
end

-- Bouton « Option » du HUD : le petit HUD disparaît, la grande fenêtre apparaît (K pour la fermer).
function M.openBig()
  refreshMode()
  if not modeInfo.session then return false end
  bigOpen, hudOpen = true, false
  slog('info', 'You opened the big window (Option button).')
  toast(L('Pour fermer l\'interface, appuyez sur ', 'To close the interface, press ') .. grnfr_keys.getDisplay() .. '.')
  pushStatic(true)
  return true
end
function M.closeBig() bigOpen = false; slog('info', 'You closed the big window.'); pushStatic(true); return true end

-- Appelé par l'UI au chargement de l'application.
local function onlyOverlay()
  local n = 0
  for _ in pairs(consumers) do n = n + 1 end
  return n == 1 and consumers.overlay == true
end
-- Cadence rapide (à chaque image) seulement si le HUD est ouvert ou si une UI détaillée (fenêtre, app) s'est abonnée.
-- Sinon : une mesure toutes les 0,5 s, envoyée même sans abonnement (l'abonnement UI -> Lua n'est pas fiable).
local function needFast()
  if hudOpen then return true end
  for id in pairs(consumers) do if id ~= 'overlay' and id ~= 'welcome' then return true end end
  return false
end

function M.requestState(id)
  consumers[id or 'angular'] = true
  uiAttached = true
  refreshMode()
  pushStatic()
  return buildStatic()
end

-- Lecture directe de l'état par l'UI (sans dépendre des événements) : sert au sondage régulier du panneau.
function M.getState()
  refreshMode()
  return buildStatic()
end

function M.uiClosed(id)
  consumers[id or 'angular'] = nil
  uiAttached = next(consumers) ~= nil
  return true
end

local SETTING_NAMES = {
  hudEnabled = 'HUD enabled', showFps = 'HUD: show FPS', showAvg = 'HUD: show average FPS', showMode = 'HUD: show game mode',
  showGraph = 'HUD: show FPS graph', compact = 'HUD: compact size', refreshRate = 'HUD refresh rate (0 = automatic)',
  accent = 'Accent color', opacity = 'HUD opacity', lang = 'Language', hudPos = 'HUD position',
  fpsOverlay = 'FPS counter', fpsBg = 'FPS counter background', fpsPos = 'FPS counter position', fpsSize = 'FPS counter size',
  fpsColor = 'FPS counter color', fpsOpacity = 'FPS counter opacity', antiStutter = 'Anti-stutter', traffic = 'Adaptive traffic',
  trafficMinFps = 'Adaptive traffic minimum FPS',
}
local function valueText(v) if v == true then return 'ON' elseif v == false then return 'OFF' end return tostring(v) end

function M.setSetting(key, value)
  if grnfr_settings.set(key, value) then
    slog('info', 'Setting changed: ' .. (SETTING_NAMES[key] or tostring(key)) .. ' is now ' .. valueText(value) .. '.')
    if key == 'hudEnabled' and value == false then hudOpen = false; bigOpen = false end
    if key == 'antiStutter' then grnfr_stutter.apply(value) end
    if key == 'traffic' then grnfr_traffic.setEnabled(value) end
    pushStatic()
  else
    slog('warn', 'A setting change was refused (' .. tostring(key) .. ' = ' .. tostring(value) .. ' is not a valid value).')
    return false
  end
  return true
end

function M.resetSettings()
  local cur = grnfr_settings.get()
  local lang, chosen, intro = cur.lang, cur.langChosen, cur.introShown -- langue et notification ne sont pas réinitialisées
  grnfr_settings.reset()
  slog('info', 'All settings were reset to their default values.')
  grnfr_settings.set('lang', lang)
  grnfr_settings.set('langChosen', chosen)
  grnfr_settings.set('introShown', intro)
  pushStatic()
  return true
end

-- Premier lancement : choix de la langue (mémorisé, l'écran d'accueil ne revient plus).
function M.chooseLanguage(lang)
  if lang ~= 'fr' and lang ~= 'en' then return end
  grnfr_settings.set('lang', lang)
  grnfr_settings.set('langChosen', true)
  slog('info', 'Language set to ' .. (lang == 'en' and 'English' or 'French') .. '.')
  pushStatic()
  return true
end

-- Appelé par le bouton du menu principal (ui/ui-vue/mods/GRNFR/index.js).
function M.showInfo()
  local msg = 'v' .. VERSION .. ' | ' .. L('Touche du HUD : ', 'HUD key: ') .. grnfr_keys.getDisplay()
    .. ' | ' .. L('HUD App : Pause > System > HUD Apps', 'HUD App: Pause > System > HUD Apps')
  pcall(function()
    guihooks.trigger('toastrMsg', { type = 'info', title = 'GRNFR CMP', msg = msg })
  end)
end

local function onStateEvent()
  refreshMode()
  pushStatic()
end

-- Changement de carte : l'état en cours (trafic) est réinitialisé, mais le RÉGLAGE « trafic adaptatif »
-- reste enregistré tel que le joueur l'a choisi (il est réarmé automatiquement dans tick).
local function resetGameplayFeatures()
  grnfr_traffic.reset()
  pcall(grnfr_taxi.reset); pcall(grnfr_taxibot.reset); pcall(grnfr_bus.reset); pcall(grnfr_online.reset); pcall(grnfr_ghosts.reset); pcall(grnfr_places.reset); pcall(grnfr_facilities.reset)
  pcall(grnfr_garage.reset); pcall(grnfr_convoy.reset); pcall(grnfr_chat.reset); pcall(grnfr_drag.reset); pcall(grnfr_track.reset)
  if onlineOpen then onlineOpen = false; guihooks.trigger('GRNFROnlineWin', { open = false }) end
  if tabletOpen then tabletOpen = false; guihooks.trigger('GRNFRTabletWin', { open = false }) end
  if quickOpen then quickOpen = false; guihooks.trigger('GRNFRQuickWin', { open = false }) end
  sessionAge = 0
end
function M.onClientStartMission() notified, notifyAcc = false, 0; resetGameplayFeatures(); onStateEvent() end
function M.onClientEndMission()
  notified, notifyAcc = false, 0
  resetGameplayFeatures()
  if wasSession then wasSession = false; pcall(grnfr_sessionlog.finish, 'The map was closed.') end
  onStateEvent()
end

function M.onVehicleSwitched(oldId, newId, player)
  pcall(grnfr_online.onVehicleSwitched, oldId, newId)
  onStateEvent()
end
M.onSettingsChanged = onStateEvent
M.onInputBindingsChanged = onStateEvent

-- Hook de rendu : dtReal = durée réelle de l'image (inclut la pause).
-- onUpdate sert de repli si onPreRender n'est jamais appelé (jamais les deux).
local preRenderSeen = false
function M.onUpdate(dtReal)
  cntUpd = cntUpd + 1
  if not preRenderSeen then M.tick(dtReal) end
end
function M.onPreRender(dtReal)
  cntPre = cntPre + 1
  preRenderSeen = true
  M.tick(dtReal)
end

-- Secours : si ni onUpdate ni onPreRender ne sont jamais appelés par le jeu, l'UI appelle cette fonction à chaque image
-- et la durée est mesurée avec un chronomètre. Sans effet (renvoie 'hooks') dès que les hooks du jeu fonctionnent.
local pollTimer, inPoll, pollLogged = nil, false, false
function M.uiPoll()
  if cntPre + cntUpd > 0 then return 'hooks' end
  if not pollLogged then pollLogged = true; slog('warn', 'The game did not call the mod every frame, so FPS is now measured through the interface (backup mode). FPS numbers may be less precise.') end
  local ok, ms = pcall(function()
    if not pollTimer then pollTimer = hptimer() return nil end
    return pollTimer:stopAndReset()
  end)
  if not ok or type(ms) ~= 'number' or ms < 4 then return 'wait' end -- < 4 ms : appel en double dans la même image
  cntPoll = cntPoll + 1
  inPoll = true
  M.tick(ms / 1000)
  inPoll = false
  return 'poll'
end
-- Notification affichée UNE SEULE FOIS (introShown, mémorisé dans settings/grnfr.json), au premier lancement
-- d'une partie, quel que soit le mode de jeu.
local function notifyStart()
  local key = grnfr_keys.getDisplay()
  local msg = L('Appuyez sur ', 'Press ') .. key .. L(' pour ouvrir / fermer le HUD GRNFR.', ' to open / close the GRNFR HUD.')
    .. L(' (modifiable : Options > Contrôles > « GRNFR CMP »)', ' (changeable: Options > Controls > "GRNFR CMP")')
  pcall(function()
    guihooks.trigger('toastrMsg', { type = 'info', title = 'GRNFR CMP', msg = msg })
  end)
  grnfr_settings.set('introShown', true)
  slog('info', 'Showed the one-time tip about the HUD key.')
end

-- Chronomètre de secours : si le hook de jeu ne fournit pas de durée d'image valide, on la mesure nous-mêmes.
local timer = nil
local function fallbackDt()
  local ok, ms = pcall(function()
    if not timer then timer = hptimer() return nil end
    return timer:stopAndReset()
  end)
  if ok and type(ms) == 'number' and ms > 0 then return ms / 1000 end
end
local loggedDt = false

function M.tick(dtReal)
  if type(dtReal) ~= 'number' or dtReal ~= dtReal or dtReal <= 0 then
    dtReal = fallbackDt() or dtReal
    if not loggedDt then loggedDt = true; slog('warn', 'The game gave an invalid frame time, so the mod uses its own timer instead.') end
  elseif timer then
    pcall(function() timer:stopAndReset() end) -- garde le chronomètre synchronisé
  end
  grnfr_perf.sample(dtReal)
  do -- option en développement : trafic adaptatif
    local cfg0 = grnfr_settings.get()
    local pm = grnfr_perf.get()
    if cfg0.traffic then
      grnfr_traffic.update(tonumber(dtReal) or 0, pm and pm.avg or nil, cfg0.trafficMinFps)
      -- état « impossible » : on le laisse affiché (le réglage reste coché), le changement d'état est poussé à l'UI par la signature
    end
  end
  do -- GRNFR Online : actif seulement dans une partie où il est autorisé
    local d0 = tonumber(dtReal) or 0
    if d0 > 0.5 then d0 = 0.5 end
    if modeInfo.session and grnfr_online.isAuthed() then
      grnfr_taxi.update(d0); grnfr_taxibot.update(d0); grnfr_bus.update(d0); grnfr_garage.update(d0)
      grnfr_chat.update(d0); grnfr_drag.update(d0); grnfr_roadmap.update(d0)
    end
    grnfr_nav.update()
    grnfr_http.update(d0)
    grnfr_online.update(d0)
    grnfr_travel.update(d0)
    if tabletOpen and not grnfr_garage.isNear() then setTabletOpen(false) end -- on s'est éloigné du garage
    if modeInfo.session and grnfr_online.isAuthed() then grnfr_ghosts.update(d0); grnfr_convoy.update(d0); grnfr_track.update() end
  end
  if wasSession then grnfr_sessionlog.update(tonumber(dtReal) or 0, (grnfr_perf.get() or {}).avg) end
  if modeInfo.session then
    if not notified and not grnfr_settings.get().introShown then
      notifyAcc = notifyAcc + (tonumber(dtReal) or 0)
      if notifyAcc >= 5 then -- laisse le temps au mode (jeu libre / carrière) de se stabiliser
        notified = true
        refreshMode()
        if modeInfo.session then notifyStart() end
      end
    end
  else
    notified, notifyAcc = false, 0
  end
  local dt = tonumber(dtReal) or 0
  acc, modeAcc = acc + dt, modeAcc + dt
  if modeInfo.session then sessionAge = sessionAge + dt else sessionAge = 0 end
  local cfg = grnfr_settings.get()
  -- cadence de mise à jour du HUD : 0 = automatique (à chaque image, aucune limite), sinon N fois par seconde
  local period = (cfg.refreshRate or 0) > 0 and 1 / cfg.refreshRate or 0
  if not needFast() then period = 0.5 end -- compteur FPS / fenêtre : une valeur toutes les 0,5 s suffit
  if modeAcc >= 1 then -- le mode de jeu est relu une fois par seconde (pas à chaque image)
    modeAcc = 0
    refreshMode()
    -- réglage trafic enregistré = coché : on (ré)arme le trafic adaptatif quelques secondes après l'entrée en partie
    if modeInfo.session and sessionAge >= 5 and grnfr_settings.get().traffic and grnfr_traffic.status().state == 'off' then
      grnfr_traffic.setEnabled(true)
    end
    local tr = grnfr_traffic.status()
    local sig = table.concat(modeInfo.ids or {}, '+') .. tostring(modeInfo.raw) .. tostring(modeInfo.session)
      .. '|' .. tr.state .. tr.active .. '/' .. tr.parked
    staticAcc = staticAcc + 1
    if sig ~= lastSig or staticAcc >= 1 then lastSig = sig; staticAcc = 0; pushStatic() end
  end
  if acc < period then return end
  acc = period > 0 and math.min(acc - period, period) or 0 -- garde le reste : la limite est respectée au plus près
  local m = grnfr_perf.get()
  cntSent = cntSent + 1
  guihooks.trigger('GRNFRTick', {
    poll = inPoll,
    hooks = cntPre + cntUpd,
    valid = m ~= nil,
    fps = m and m.instant or 0,
    avg = m and m.avg or 0,
    frames = m and m.frames or 0,
  })
end

function M.onExtensionLoaded()
  pcall(function() grnfr_stutter.apply(grnfr_settings.get().antiStutter) end)
end

function M.onExtensionUnloaded()
  pcall(grnfr_settings.flush)
  wasSession = false
  pcall(grnfr_sessionlog.finish, 'The mod was unloaded.')
  pcall(grnfr_taxi.reset); pcall(grnfr_taxibot.reset); pcall(grnfr_bus.reset); pcall(grnfr_online.reset); pcall(grnfr_ghosts.reset)
  pcall(grnfr_garage.reset); pcall(grnfr_convoy.reset); pcall(grnfr_chat.reset); pcall(grnfr_drag.reset); pcall(grnfr_track.reset)
  pcall(grnfr_stutter.apply, false)
  if guihooks then guihooks.trigger('GRNFRStatic', { session = false, hudOpen = false }) end
  grnfr_perf.reset()
end

return M
