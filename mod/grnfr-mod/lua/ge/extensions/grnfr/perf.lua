-- Mesure FPS : fenêtre glissante ~1 s fondée sur les durées réelles d'image.
-- avg = nombre d'images / somme des durées (PAS une moyenne de FPS instantanés).
local M = {}
local WINDOW, MAX_DT = 1.0, 1.0
local q, head, tail, sum, lastInstant = {}, 1, 0, 0, nil

function M.reset() q, head, tail, sum, lastInstant = {}, 1, 0, 0, nil end

function M.sample(dt)
  -- Valeur invalide ou trou (chargement, gel > 1 s) : on repart d'une fenêtre vide.
  if type(dt) ~= 'number' or dt ~= dt or dt <= 0 or dt > MAX_DT then M.reset() return end
  tail = tail + 1; q[tail] = dt; sum = sum + dt; lastInstant = 1 / dt
  while tail > head and (sum - q[head]) >= WINDOW do
    sum = sum - q[head]; q[head] = nil; head = head + 1
  end
end

function M.get()
  local n = tail - head + 1
  if n < 2 or sum <= 0 then return nil end
  return { instant = lastInstant, avg = n / sum, frames = n, window = sum }
end

return M
