-- GRNFR CPM - session log.
-- Writes ONE plain-English text file per play session (from loading a map until leaving it) to:
--   <BeamNG user folder>/settings/grnfr/logs/
-- The file is a simple diary: what you clicked, what the mod did, and anything that went wrong.
-- Nothing personal is written: no user name, no folder paths, no PC hardware information.
-- The 10 newest log files are kept; older ones are deleted automatically.
local M = {}

local DIR = 'settings/grnfr/logs/'
local KEEP_FILES = 10     -- how many session files to keep
local MAX_LINES = 600     -- safety limit for one session
local FLUSH_EVERY = 5     -- seconds between disk writes (also written when the session ends)

local lines, nLines, path = {}, 0, nil
local active, dirty, writeFailed, capNoted = false, false, false, false
local t0, tFlush, lastEnd = 0, 0, 0
local nWarn, nProblem = 0, 0
local pre = {} -- messages received before a session starts (shown at the top of the next session file)
local totTime, totFrames, lowFps = 0, 0, nil
local minTime, minFrames, minLow = 0, 0, nil
local nextMinute = 60

local SEP = string.rep('-', 60)

local function elapsed() return math.max(0, os.time() - t0) end
local function stamp(sec) return string.format('%02d:%02d', math.floor(sec / 60), sec % 60) end
local function duration(sec) return string.format('%d min %02d s', math.floor(sec / 60), sec % 60) end

local function raw(text)
  nLines = nLines + 1
  lines[#lines + 1] = text
  dirty = true
end

function M.flush()
  if not active and not path then return end
  if not path or not dirty or writeFailed then return end
  local ok = pcall(function() writeFile(path, table.concat(lines, '\n') .. '\n') end)
  if ok then dirty = false else writeFailed = true end -- if the disk is not writable, stop trying (no crash, no spam)
  tFlush = 0
end

-- Deletes the oldest log files so that only the newest KEEP_FILES remain.
local function prune()
  pcall(function()
    local files = FS:findFiles(DIR, '*.log', 0, true, false)
    if type(files) ~= 'table' or #files <= KEEP_FILES then return end
    table.sort(files) -- file names start with the date, so alphabetical = oldest first
    for i = 1, #files - KEEP_FILES do pcall(function() FS:removeFile(files[i]) end) end
  end)
end

-- info = { mode = 'Free roam', map = 'west_coast_usa', modVersion = '0.9.0', gameVersion = '0.xx' }
function M.begin(info)
  if active then M.finish('A new session started.') end
  if os.time() - lastEnd < 2 then return end -- ignore a restart right after the end of a session
  info = info or {}
  lines, nLines, dirty, writeFailed, capNoted = {}, 0, true, false, false
  nWarn, nProblem = 0, 0
  totTime, totFrames, lowFps, minTime, minFrames, minLow, nextMinute = 0, 0, nil, 0, 0, nil, 60
  t0, tFlush = os.time(), 0
  path = DIR .. os.date('%Y-%m-%d_%H-%M-%S') .. '.log'
  pcall(function() FS:directoryCreate(DIR, true) end)
  active = true
  raw('============================================================')
  raw(' GRNFR CPM - session log')
  raw('============================================================')
  raw(' This file is a simple diary of what the mod did during one play session.')
  raw(' Nothing personal is saved here (no name, no folder paths, no PC hardware info).')
  raw(' Times like [03:25] mean "3 minutes 25 seconds after the session started".')
  raw(' Lines starting with WARNING or PROBLEM are the important ones.')
  raw(' If something does not work, send this file to the mod author.')
  raw(SEP)
  raw(' Mod version : ' .. tostring(info.modVersion or '?'))
  raw(' Game version: ' .. tostring(info.gameVersion or 'unknown'))
  raw(' Date        : ' .. os.date('%Y-%m-%d %H:%M:%S'))
  raw(' Map         : ' .. tostring(info.map or 'unknown'))
  raw(' Game mode   : ' .. tostring(info.mode or 'unknown'))
  raw(SEP)
  if #pre > 0 then
    raw('Messages from before this session started:')
    for _, l in ipairs(pre) do
      raw('  ' .. l)
      if l:find('^WARNING') then nWarn = nWarn + 1 elseif l:find('^PROBLEM') then nProblem = nProblem + 1 end
    end
    raw(SEP)
    pre = {}
  end
  raw('[00:00] Session started.')
  M.flush()
end

-- kind = 'info' | 'warn' | 'problem'
function M.add(kind, text)
  text = tostring(text)
  local prefix = ''
  if kind == 'warn' then prefix = 'WARNING: ' elseif kind == 'problem' then prefix = 'PROBLEM: ' end
  if not active then
    if prefix ~= '' and #pre < 10 then pre[#pre + 1] = prefix .. text end
    return
  end
  if kind == 'warn' then nWarn = nWarn + 1 elseif kind == 'problem' then nProblem = nProblem + 1 end
  if nLines >= MAX_LINES then
    if not capNoted then capNoted = true; raw('[' .. stamp(elapsed()) .. '] The log is full: further messages are not recorded.') end
    return
  end
  raw('[' .. stamp(elapsed()) .. '] ' .. prefix .. text)
end

-- Called every frame by the mod: dt = frame time (s), avg = average FPS over the last second (or nil).
function M.update(dt, avg)
  if not active then return end
  dt = tonumber(dt) or 0
  tFlush = tFlush + dt
  if type(avg) == 'number' and avg == avg and avg > 0 and dt > 0 and dt < 1 then
    totTime, totFrames = totTime + dt, totFrames + 1
    minTime, minFrames = minTime + dt, minFrames + 1
    if totTime > 3 then -- ignore the first seconds (map still loading)
      if not lowFps or avg < lowFps then lowFps = avg end
      if not minLow or avg < minLow then minLow = avg end
    end
  end
  local e = elapsed()
  if e >= nextMinute then
    nextMinute = e + 60
    if minFrames > 0 and minTime > 0 and minLow then
      M.add('info', string.format('FPS during the last minute: %d on average, %d at the lowest.', math.floor(minFrames / minTime + 0.5), math.floor(minLow + 0.5)))
    end
    minTime, minFrames, minLow = 0, 0, nil
  end
  if dirty and tFlush >= FLUSH_EVERY then M.flush() end
end

function M.finish(reason)
  if not active then return end
  raw(SEP)
  raw('Session ended: ' .. tostring(reason or 'unknown reason'))
  raw('Duration  : ' .. duration(elapsed()))
  if totFrames > 0 and totTime > 0 then
    raw(string.format('Average FPS for the whole session: %d (lowest 1-second average: %d)', math.floor(totFrames / totTime + 0.5), math.floor((lowFps or 0) + 0.5)))
  end
  raw(string.format('Warnings: %d   Problems: %d', nWarn, nProblem))
  raw(SEP)
  M.flush()
  active = false
  lastEnd = os.time()
  prune()
end

function M.onExtensionUnloaded() M.finish('The mod was unloaded.') end

return M
