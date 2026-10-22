-- Paramètres validés + persistance JSON (settings/grnfr.json).
local M = {}
local PATH = 'settings/grnfr.json'
local saveWarned = false
local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

local SCHEMA = {
  hudEnabled   = { t = 'bool', d = true },
  showFps      = { t = 'bool', d = true },
  showAvg      = { t = 'bool', d = true },
  showMode     = { t = 'bool', d = true },
  showGraph    = { t = 'bool', d = true },
  compact      = { t = 'bool', d = false },
  -- 0 = automatique : le HUD se met à jour à la cadence des images du PC ; sinon N fois par seconde
  refreshRate  = { t = 'enum', d = 0, values = { [0] = true, [1] = true, [2] = true, [4] = true, [10] = true } },
  accent       = { t = 'enum', d = 'orange', values = { orange = true, cyan = true, green = true, amber = true, violet = true } },
  opacity      = { t = 'num', d = 1, min = 0.5, max = 1 },
  -- Langue : choisie au premier lancement (langChosen), mémorisée dans settings/grnfr.json
  lang         = { t = 'enum', d = 'fr', values = { fr = true, en = true } },
  langChosen   = { t = 'bool', d = false },
  -- Compteur FPS (visible en jeu, indépendant du HUD)
  fpsOverlay   = { t = 'bool', d = false },
  fpsBg        = { t = 'bool', d = true },
  fpsPos       = { t = 'enum', d = 'top-right', values = { ['top-right'] = true, ['top-left'] = true, ['bottom-right'] = true, ['bottom-left'] = true } },
  fpsSize      = { t = 'enum', d = 'medium', values = { small = true, medium = true, large = true } },
  fpsColor     = { t = 'color', d = '#ff6600' },
  fpsOpacity   = { t = 'num', d = 0.9, min = 0.3, max = 1 },
  introShown   = { t = 'bool', d = false }, -- notification « touche du HUD » affichée une seule fois, jamais réinitialisée
  -- Optimisation (en développement)
  antiStutter  = { t = 'bool', d = false },
  -- Position du HUD en jeu (touche K)
  hudPos       = { t = 'enum', d = 'top-left', values = { ['top-left'] = true, ['top-right'] = true, ['bottom-left'] = true, ['bottom-right'] = true } },
}

local cur = {}
local function copyDefault(d)
  if type(d) ~= 'table' then return d end
  local c = {}
  for i, v in ipairs(d) do c[i] = v end
  return c
end
local function defaults() local t = {} for k, s in pairs(SCHEMA) do t[k] = copyDefault(s.d) end return t end

local function valid(k, v)
  local s = SCHEMA[k]
  if not s then return false end
  if s.t == 'bool' then return type(v) == 'boolean' end
  if s.t == 'enum' then return s.values[v] == true end
  if s.t == 'num' then return type(v) == 'number' and v == v and v >= s.min and v <= s.max end
  if s.t == 'color' then return type(v) == 'string' and v:match('^#%x%x%x%x%x%x$') ~= nil end
  if s.t == 'idlist' then
    if type(v) ~= 'table' then return false end
    for _, id in pairs(v) do if type(id) ~= 'string' or s.values[id] ~= true then return false end end
    return true
  end
end

-- Écriture sur disque (settings/grnfr.json) à chaque changement : les réglages survivent à la fermeture du jeu.
-- Les échecs sont journalisés (avant, ils étaient ignorés en silence).
local function save()
  local ok, res = false, nil
  if jsonWriteFile then ok, res = pcall(jsonWriteFile, PATH, cur, true) end
  if not ok or res == false then
    if not saveWarned then -- one message is enough: the same problem would repeat at every change
      saveWarned = true
      slog('problem', 'Your settings could not be saved to disk. They will be forgotten when you close the game.')
    end
    return false
  end
  return true
end

local function load()
  cur = defaults()
  if not jsonReadFile then return end
  local ok, data = pcall(jsonReadFile, PATH)
  if (not ok or type(data) ~= 'table') and readFile and jsonDecode then -- repli : lecture du texte brut
    local ok2, txt = pcall(readFile, PATH)
    if ok2 and type(txt) == 'string' and txt ~= '' then
      local ok3, d2 = pcall(jsonDecode, txt)
      if ok3 and type(d2) == 'table' then ok, data = true, d2 end
    end
  end
  if ok and type(data) == 'table' then
    for k, v in pairs(data) do if valid(k, v) then cur[k] = v end end
  end
end

function M.get() return cur end
function M.flush() return save() end
function M.set(k, v) if not valid(k, v) then return false end cur[k] = v save() return true end
function M.reset() cur = defaults() save() end
function M.onExtensionLoaded() load() end
load()
return M
