-- Anti-stutter (EN DÉVELOPPEMENT) : lisse le ramasse-miettes Lua du jeu (cycles plus fréquents et plus courts).
-- N'agit que sur la mémoire Lua de la partie « jeu » (pas sur la physique des véhicules ni sur le disque).
-- Effet non vérifié en jeu ; désactiver restaure les valeurs d'origine.
local M = {}
local orig = nil
local function slog(kind, msg) local sl = rawget(_G, 'grnfr_sessionlog') if sl then pcall(sl.add, kind, msg) end end

function M.apply(on)
  if on and not orig then
    local ok, p, s = pcall(function()
      local p = collectgarbage('setpause', 110)
      local s = collectgarbage('setstepmul', 300)
      return p, s
    end)
    if ok then
      orig = { pause = p, stepmul = s }
      slog('info', 'Anti-stutter is ON: the game memory cleaner now runs more often, in shorter steps.')
    else
      slog('warn', 'Anti-stutter could not be turned on (the game refused the memory cleaner change).')
    end
  elseif not on and orig then
    pcall(function()
      collectgarbage('setpause', orig.pause or 200)
      collectgarbage('setstepmul', orig.stepmul or 200)
    end)
    orig = nil
    slog('info', 'Anti-stutter is OFF: the game memory cleaner is back to its original settings.')
  end
end

function M.isOn() return orig ~= nil end
return M
