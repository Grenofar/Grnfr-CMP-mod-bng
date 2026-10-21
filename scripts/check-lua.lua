-- Vérifie la syntaxe de tous les .lua passés en argument (texlua / lua). Usage : texlua scripts/check-lua.lua fichier...
local bad = 0
for _, f in ipairs(arg) do
  local fn, err = loadfile(f)
  if not fn then print('SYNTAXE  ' .. tostring(err)); bad = bad + 1 end
end
print(bad == 0 and ('OK : ' .. #arg .. ' fichiers Lua') or (bad .. ' erreur(s)'))
os.exit(bad == 0 and 0 or 1)
