-- GRNFR Online : export / import de profil. Le "profil" exporté n'est RIEN d'autre que le jeton de
-- connexion déjà détenu par l'interface (voir net.js) : c'est lui qui prouve qui vous êtes (comme un mot de
-- passe), pas une copie de votre argent ou de votre garage, qui restent décidés par le serveur et jamais
-- dupliqués ici. Écrit/lu sous forme de fichier sur cette machine (settings/grnfr/profiles/) : pour jouer sur
-- un autre PC, copiez ce fichier là-bas (clé USB, etc.) puis utilisez "Importer un profil".
local M = {}

local DIR = 'settings/grnfr/profiles/'
local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

local function safeName(s)
  s = tostring(s or ''):gsub('[^A-Za-z0-9_-]', '_')
  if s == '' then s = 'profile' end
  return s
end

-- data = { username = "...", refresh = "<jeton>" }. Écrit settings/grnfr/profiles/<pseudo>.grnfrprofile.json.
function M.export(data)
  if type(data) ~= 'table' or type(data.refresh) ~= 'string' or data.refresh == '' then return false end
  pcall(function() FS:directoryCreate(DIR, true) end)
  local path = DIR .. safeName(data.username) .. '.grnfrprofile.json'
  local ok = pcall(jsonWriteFile, path, data, true)
  if ok then slog('info', 'Profile exported to ' .. path .. '.') end
  return ok, path
end

-- Liste les profils trouvés sur cette machine : [{ path, username }].
function M.list()
  local out = {}
  pcall(function()
    local files = FS:findFiles(DIR, '*.grnfrprofile.json', 0, true, false)
    for _, f in ipairs(files or {}) do
      local ok, d = pcall(jsonReadFile, f)
      if ok and type(d) == 'table' and type(d.username) == 'string' then
        out[#out + 1] = { path = f, username = d.username }
      end
    end
  end)
  return out
end

-- Relit un fichier de profil (chemin renvoyé par M.list). Renvoie { username, refresh } ou nil.
function M.read(path)
  if type(path) ~= 'string' or path == '' then return nil end
  local ok, d = pcall(jsonReadFile, path)
  if ok and type(d) == 'table' and type(d.refresh) == 'string' then return d end
end

return M
