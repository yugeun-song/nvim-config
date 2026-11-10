-- Windows only: vim.fn.executable() and vim.fn.exepath() with a memory. Windows tries every PATHEXT extension in every
-- PATH directory, about 10 ms a name with forty directories where Linux takes microseconds, and the startup, each
-- vim.system() spawn (it resolves the program first), linters and formatters all ask. Answers for bare names are kept
-- per PATH (Mason prepends its bin once loaded) in stdpath("cache")/nvim-config/executable_lookup_cache.json, with the
-- mtime of each directory on that PATH; a program added to or removed from a directory changes it. Checked once per
-- PATH at startup and again whenever two seconds have passed since, one stat per directory (about 2 ms for sixty), so a
-- program installed meanwhile is seen. A directory that changed is listed once and only the answers it can affect are
-- dropped: a miss it now has a candidate for, a hit it held or now shadows. Some programs write into their own
-- directory on PATH all the time (IncrediBuild's agent, every few seconds); that costs one listing instead of every
-- answer. A name with a directory in it goes to the real functions every time, and so does a hit outside PATH,
-- except one in the current directory (with cmd.exe as 'shell', Neovim may search it first): PATH alone answers then.
local M = {}

local uv = vim.uv
local FILE = require("features.util.storage").path("cache", "executable_lookup_cache.json")
-- PATH variants: Mason's bin before or after it loads, times the environments Neovim starts from (a terminal,
-- Neovide from the Start menu, an editor launched by another program).
local KEEP = 8
local RECHECK_MS = 2000

local raw_exepath, raw_executable = vim.fn.exepath, vim.fn.executable

local disk -- executable_lookup_cache.json: { [PATH] = { mtimes, names, used } }, read once
local live = {} -- { [PATH] = { dirs, index, mtimes, names, checked } }
local save_pending = false

local function key(path)
  return vim.fs.normalize(path):lower()
end

local function mtime_of(dir)
  local st = uv.fs_stat(dir)

  return st and ("%d.%d"):format(st.mtime.sec, st.mtime.nsec) or "-"
end

-- The lower-case names in a directory, or false when it cannot be read.
local function listing(dir)
  local fs = uv.fs_scandir(dir)

  if not fs then
    return false
  end

  local set = {}

  while true do
    local name = uv.fs_scandir_next(fs)

    if not name then
      return set
    end

    set[name:lower()] = true
  end
end

local pathext, is_pathext

local function load_pathext()
  if not pathext then
    pathext, is_pathext = {}, {}
    for ext in vim.gsplit((uv.os_getenv("PATHEXT") or ".COM;.EXE;.BAT;.CMD"):lower(), ";", { trimempty = true }) do
      pathext[#pathext + 1] = ext
      is_pathext[ext] = true
    end
  end
end

-- The file names Windows would accept for name: itself and name with each PATHEXT extension.
local function candidates(name)
  load_pathext()

  local lower = name:lower()
  local list = { lower }

  for _, ext in ipairs(pathext) do
    list[#list + 1] = lower .. ext
  end

  return list
end

-- Drops the answers the directories changed since the last check can affect, and records their new mtimes.
local function revalidate(entry)
  local changed = {}

  for i, dir in ipairs(entry.dirs) do
    local m = mtime_of(dir)

    if m ~= entry.mtimes[i] then
      changed[#changed + 1] = i
      entry.mtimes[i] = m
    end
  end

  -- Nothing remembered (a PATH not seen before): nothing to drop, and no directory needs listing.
  if #changed == 0 or next(entry.names) == nil then
    return
  end

  local sets = {}

  for _, i in ipairs(changed) do
    sets[i] = listing(entry.dirs[i])
  end

  for name, found in pairs(entry.names) do
    local at = found and entry.index[key(vim.fs.dirname(found))] or math.huge

    for _, i in ipairs(changed) do
      local set = sets[i]
      local stale = false

      if i == at then
        stale = not (set and set[vim.fs.basename(found):lower()])
      elseif i < at and set then
        for _, file in ipairs(candidates(name)) do
          if set[file] then
            stale = true

            break
          end
        end
      end

      if stale then
        entry.names[name] = nil

        break
      end
    end
  end
end

-- The lookups run in fast event contexts too (vim.system() resolves its program there), where no Vimscript
-- function may be called: io, luv and vim.json only, until save() runs on the main loop.
local function read_disk()
  local f = io.open(FILE, "rb")

  if not f then
    return {}
  end

  local text = f:read("*a")

  f:close()

  local ok, data = pcall(vim.json.decode, text)

  return ok and type(data) == "table" and data or {}
end

local function entry_for(path)
  local entry = live[path]

  if entry then
    if uv.now() - entry.checked > RECHECK_MS then
      revalidate(entry)
      entry.checked = uv.now()
    end

    return entry
  end

  disk = disk or read_disk()

  local dirs, index = {}, {}

  for dir in vim.gsplit(path, ";", { plain = true, trimempty = true }) do
    dirs[#dirs + 1] = dir
    index[key(dir)] = index[key(dir)] or #dirs
  end

  local saved = disk[path]
  local reuse = type(saved) == "table"
    and type(saved.names) == "table"
    and type(saved.mtimes) == "table"
    and #saved.mtimes == #dirs

  entry = {
    dirs = dirs,
    index = index,
    mtimes = reuse and saved.mtimes or {},
    names = reuse and saved.names or {},
    checked = uv.now(),
  }

  live[path] = entry
  revalidate(entry)

  return entry
end

local function save()
  save_pending = false

  for path, entry in pairs(live) do
    disk[path] = { mtimes = entry.mtimes, names = entry.names, used = os.time() }
  end

  local paths = vim.tbl_keys(disk)

  table.sort(paths, function(a, b)
    return (disk[a].used or 0) > (disk[b].used or 0)
  end)

  for i = KEEP + 1, #paths do
    disk[paths[i]] = nil
  end

  vim.fn.mkdir(vim.fs.dirname(FILE), "p")
  pcall(vim.fn.writefile, { vim.json.encode(disk) }, FILE)
end

local function is_runnable(path)
  load_pathext()

  return is_pathext[(path:match("%.[^.\\/]+$") or ""):lower()] == true
end

-- PATH alone, as cmd.exe searches it: each directory in turn, each PATHEXT extension in order (none if name has one).
local function search_path(name)
  local exts = is_runnable(name) and { "" } or pathext

  for dir in vim.gsplit(uv.os_getenv("PATH") or "", ";", { plain = true, trimempty = true }) do
    local base = dir:gsub("[/\\]+$", "") .. "\\" .. name

    for _, ext in ipairs(exts) do
      local st = uv.fs_stat(base .. ext)

      if st and st.type == "file" then
        return base .. ext
      end
    end
  end

  return ""
end

-- exepath() can answer with a file Windows cannot start (npm puts an extensionless sh script beside each .cmd it
-- installs; CreateProcess appends .exe to it), or with one from the current directory, tried before PATH (a cl.exe
-- planted in a repository would build the helper). PATH alone answers then, the current directory only if listed.
local function runnable_on_path(name, found)
  local cwd = uv.cwd()

  if found == "" or (is_runnable(found) and not (cwd and key(vim.fs.dirname(found)) == key(cwd))) then
    return found
  end

  return search_path(name)
end

---@param name string
---@return string
function M.exepath(name, ...)
  if type(name) ~= "string" or name == "" or name:find("[/\\]") or select("#", ...) > 0 then
    return raw_exepath(name, ...)
  end

  local entry = entry_for(uv.os_getenv("PATH") or "")
  local hit = entry.names[name]

  -- A remembered hit Windows cannot start (written before runnable_on_path existed) is looked up again.
  if hit == false then
    return ""
  elseif type(hit) == "string" and is_runnable(hit) then
    return hit
  end

  local found = runnable_on_path(name, raw_exepath(name))

  if found == "" or entry.index[key(vim.fs.dirname(found))] then
    entry.names[name] = found ~= "" and found or false
    if not save_pending then
      save_pending = true
      vim.defer_fn(save, 3000)
    end
  end

  return found
end

---@param name string
---@return integer
function M.executable(name, ...)
  if type(name) ~= "string" or name == "" or name:find("[/\\]") or select("#", ...) > 0 then
    return raw_executable(name, ...)
  end

  return M.exepath(name) ~= "" and 1 or 0
end

-- Replaces vim.fn's two for every Lua caller from here on: this config, the plugins and vim.system().
function M.install()
  vim.fn.exepath = M.exepath
  vim.fn.executable = M.executable
end

return M
