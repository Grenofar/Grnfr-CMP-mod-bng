-- GRNFR Online : fiche d'un véhicule pour la tablette (nom, marque, type, poids, puissance, transmission, description,
-- image d'aperçu), lue dans les données du jeu : core_vehicles.getModel(modèle) -> { model = infos du modèle,
-- configs = { [config] = infos de la configuration, dont preview = chemin de l'image } } (comme la concession de la
-- carrière). API non vérifiée en jeu, sous pcall ; un champ absent est simplement omis.
local M = {}

local cache = {}

local function str(x) if type(x) == 'string' and x ~= '' then return x end end
local function num(x) x = tonumber(x) if x and x == x then return x end end

-- Années : { min, max } ou nombre ou texte.
local function years(y)
  if type(y) == 'table' and y.min then
    return (y.min == y.max or not y.max) and tostring(y.min) or (y.min .. '–' .. y.max)
  end
  return str(y) or (num(y) and tostring(y))
end

function M.get(model, config)
  if type(model) ~= 'string' or model == '' then return nil end
  local key = model .. '|' .. tostring(config or '')
  if cache[key] then return cache[key] end
  local info = { model = model, config = config }
  pcall(function()
    local m = core_vehicles.getModel(model)
    if type(m) ~= 'table' then return end
    local mi = m.model or {}
    local ci = (config and m.configs and m.configs[config]) or {}
    local function pick(k) local v = ci[k] if v == nil or v == '' then v = mi[k] end return v end
    info.name = str(pick('Name'))
    info.brand = str(pick('Brand'))
    info.configName = str(ci.Configuration)
    info.type = str(pick('Type'))
    info.body = str(pick('Body Style'))
    info.country = str(pick('Country'))
    info.years = years(pick('Years'))
    info.weight = num(pick('Weight'))            -- kg
    info.power = num(pick('Power'))              -- unité des fiches du jeu (non vérifiée : affichée telle quelle)
    info.torque = num(pick('Torque'))
    info.drivetrain = str(pick('Drivetrain'))
    info.transmission = str(pick('Transmission'))
    info.fuel = str(pick('Fuel Type'))
    info.topSpeed = num(pick('Top Speed'))       -- m/s
    info.accel = num(pick('0-100 km/h'))         -- s
    info.description = str(ci.Description) or str(mi.Description)
    info.value = num(ci.Value)
    -- image : celle de la configuration, sinon celle du modèle
    info.preview = str(ci.preview) or str(mi.preview)
  end)
  if not info.preview then
    pcall(function()
      for _, ext in ipairs({ '.jpg', '.png' }) do
        local p = '/vehicles/' .. model .. '/' .. (config or 'default') .. ext
        if FS:fileExists(p) then info.preview = p break end
        p = '/vehicles/' .. model .. '/default' .. ext
        if FS:fileExists(p) then info.preview = p break end
      end
    end)
  end
  cache[key] = info
  return info
end

-- list = { { model, config }, ... } -> événement GRNFRVehInfo { items = { ["modèle|config"] = fiche } }
function M.request(list)
  local out = {}
  for i, v in ipairs(type(list) == 'table' and list or {}) do
    if i > 80 then break end
    if type(v) == 'table' then
      local info = M.get(v.model, v.config)
      if info then out[v.model .. '|' .. tostring(v.config or '')] = info end
    end
  end
  guihooks.trigger('GRNFRVehInfo', { items = out })
  return true
end

return M
