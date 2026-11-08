-- Where Neovim, this configuration, its plugins and Neovide keep what they write, and the way back to a fresh
-- clone. :ManagedPaths (<leader>uM) lists it; :ManagedPathsReset (no key) asks for "reset" to be typed, quits
-- Neovim and removes it once Neovim has exited; `nvim -l scripts/reset_to_fresh_clone.lua` asks the same in a terminal.
-- All of it is under Neovim's own directories (stdpath), apart from Neovide's window state and the
-- compile_commands.json :MsvcCompileDb writes beside a Visual Studio project. Nothing else is written: not the
-- system or user PATH, the registry or a shell profile. What Neovim adds to PATH and the environment (Mason's
-- bin, the tool shims, the MSVC environment) exists inside the running Neovim only, rebuilt at each start from
-- files listed here. Loaded on demand only.
local M = {}

local uv = vim.uv
local WIN = vim.fn.has("win32") == 1
local MAC = vim.fn.has("mac") == 1

-- What a top-level name under Neovim's directories holds. Names not here are listed without a note.
local KNOWN = {
  lazy = "plugins (lazy.nvim); lazy-lock.json in the configuration pins their versions",
  mason = "Mason's packages; mason/bin goes first on PATH inside Neovim",
  ["mason-registry-update"] = "Mason's registry check",
  site = "tree-sitter parsers and queries",
  luac = "compiled Lua modules (vim.loader)",
  shada = "history, marks, registers, jumps (ShaDa)",
  sessions = "sessions (persistence.nvim)",
  swap = "swap files",
  undo = "undo history",
  snacks = "Snacks data (picker history)",
  blink = "blink.cmp data",
  ["tree-sitter-cpp"] = "tree-sitter build files",
  ["sqlite3.dll"] = "SQLite for the Snacks picker's history, which it downloads (Windows)",
  [".netrwhist"] = "netrw's directory history",
  ["nvim-config"] = "this configuration's own files (lua/features/maintenance/local_storage.lua lists them)",
}

-- What an older layout of this configuration left directly in Neovim's directories, before its files moved to
-- their own directory.
for _, kind in ipairs(require("features.maintenance.local_storage").KINDS) do
  for name, holds in pairs(require("features.maintenance.local_storage").old_names(kind)) do
    KNOWN[name] = KNOWN[name] or ("left by an older layout of this configuration (%s); safe to remove"):format(holds)
  end
end

local function norm(path)
  return vim.fs.normalize(path)
end

local function key(path)
  path = norm(path)

  return WIN and path:lower() or path
end

-- Paths as the system writes them, for reading and copying.
function M.display(path)
  return WIN and (path:gsub("/", "\\")) or path
end

local function exists(path)
  return uv.fs_lstat(path) ~= nil
end

-- True when inner is outer or lies under it.
local function within(inner, outer)
  inner, outer = key(inner), key(outer):gsub("/$", "")

  return inner == outer or inner:sub(1, #outer + 1) == outer .. "/"
end

---@class ManagedItem
---@field group string
---@field label string
---@field path string
---@field action "remove"|"keep"|"info"
---@field note? string
---@field children? boolean  list what is directly under it
---@field kind? "stdpath"|"neovide"|"project"  what the reset may remove it as

local function env(name)
  local value = vim.env[name]

  return value ~= nil and value ~= "" and value or nil
end

-- Where Neovide keeps its two files, as its source computes them: config.toml in the xdg crate's config home on
-- Linux and macOS alike ($XDG_CONFIG_HOME/neovide, else ~/.config/neovide; %APPDATA%\neovide on Windows), or the
-- file NEOVIDE_CONFIG names; the window state in dirs::data_local_dir(), which is $XDG_DATA_HOME or
-- ~/.local/share on Linux, ~/Library/Application Support on macOS (no XDG there) and %LOCALAPPDATA% on Windows.
function M.neovide_paths()
  local home = uv.os_homedir() or ""
  local config, data

  if WIN then
    config = env("APPDATA") and vim.fs.joinpath(env("APPDATA"), "neovide")
    data = env("LOCALAPPDATA") and vim.fs.joinpath(env("LOCALAPPDATA"), "neovide")
  else
    config = vim.fs.joinpath(env("XDG_CONFIG_HOME") or vim.fs.joinpath(home, ".config"), "neovide")
    data = MAC and vim.fs.joinpath(home, "Library", "Application Support", "neovide")
      or vim.fs.joinpath(env("XDG_DATA_HOME") or vim.fs.joinpath(home, ".local", "share"), "neovide")
  end

  return { config = config and norm(config), data = data and norm(data), file = env("NEOVIDE_CONFIG") }
end

local function neovide_items()
  local paths = M.neovide_paths()
  local config, data = paths.config, { paths.data }
  local items = {}

  if paths.file and uv.fs_stat(paths.file) then
    items[#items + 1] = {
      group = "Neovide",
      label = "settings file",
      path = norm(paths.file),
      action = "keep",
      note = "NEOVIDE_CONFIG names it; Neovide reads it instead of config.toml",
    }
  end

  if config and exists(config) then
    local target = uv.fs_readlink(config)
    local st = uv.fs_lstat(config)

    items[#items + 1] = {
      group = "Neovide",
      label = "settings",
      path = norm(config),
      action = "keep",
      note = (target or (st and st.type == "link"))
          and ("a link to %s, made at installation (docs/installation.md); remove it by hand"):format(
            M.display(norm(target or uv.fs_realpath(config) or "?"))
          )
        or "Neovide's own settings; not this configuration's to remove",
    }
  end

  for _, dir in ipairs(data) do
    local file = dir and vim.fs.joinpath(dir, "neovide-settings.json")

    if file and exists(file) then
      items[#items + 1] = {
        group = "Neovide",
        label = "window state",
        path = norm(file),
        action = "remove",
        kind = "neovide",
        note = "the window size and position Neovide remembers",
      }
    end
  end

  return items
end

-- What decides this layout besides the defaults: the variables Neovim reads (on every system), and the package
-- or sandbox it runs from. { name, value, note } each; empty for the defaults.
function M.environment()
  local list = {}

  local function add(name, value, note)
    list[#list + 1] = { name = name, value = value, note = note }
  end

  if env("NVIM_APPNAME") then
    add("NVIM_APPNAME", env("NVIM_APPNAME"), "names Neovim's directories instead of nvim")
  end

  for _, var in ipairs({ "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME" }) do
    if env(var) then
      add(var, env(var), "replaces its default base directory")
    end
  end

  local flatpak = env("FLATPAK_ID")

  if flatpak or (not WIN and uv.fs_stat("/.flatpak-info")) then
    add("Flatpak", flatpak or "?", "inside its sandbox: the XDG directories are the app's, under ~/.var/app")
  end

  if env("SNAP_NAME") then
    add(
      "Snap",
      env("SNAP_NAME"),
      "a classic snap keeps the usual directories, a strict one ~/snap/" .. env("SNAP_NAME")
    )
  end

  if env("APPIMAGE") then
    add("AppImage", env("APPIMAGE"), "the usual directories")
  end

  if env("NEOVIDE_CONFIG") then
    add("NEOVIDE_CONFIG", env("NEOVIDE_CONFIG"), "Neovide's settings file")
  end

  return list
end

local function project_items()
  local items = {}
  local ok, db = pcall(require, "features.languages.c_and_cpp.msvc_toolchain.compile_database")

  for _, rec in ipairs(ok and db.databases and db.databases() or {}) do
    local st = uv.fs_stat(rec.db)

    if st then
      -- Rewritten since (by CMake, say): no longer this configuration's file.
      local ours = not rec.generated or st.mtime.sec <= rec.generated + 5

      items[#items + 1] = {
        group = "In projects (:MsvcCompileDb)",
        label = "compile_commands.json",
        path = norm(rec.db),
        action = ours and "remove" or "keep",
        kind = "project",
        note = ours and "generated from " .. vim.fs.basename(rec.project or "?")
          or "rewritten after :MsvcCompileDb wrote it; left alone",
      }
    end
  end

  return items
end

local function environment_items()
  local items = {}
  local path = os.getenv("PATH") or ""
  local sep = WIN and ";" or ":"
  local on_path = {}

  for dir in vim.gsplit(path, sep, { plain = true, trimempty = true }) do
    on_path[key(dir)] = true
  end

  local function info(label, dir, note)
    items[#items + 1] =
      { group = "PATH and environment", label = label, path = norm(dir), action = "info", note = note }
  end

  local mason_bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin")
  local shims = require("features.maintenance.local_storage").path("data", "registered_program_shims")

  if on_path[key(mason_bin)] or exists(mason_bin) then
    info("Mason", mason_bin, "first on PATH, inside Neovim only")
  end

  if on_path[key(shims)] or exists(shims) then
    info("shims", shims, "last on PATH, inside Neovim only; registered_programs.json lists them")
  end

  if WIN then
    local ok, msvc_environment = pcall(require, "features.languages.c_and_cpp.msvc_toolchain.developer_environment")
    local rec = ok and msvc_environment.read and msvc_environment.read()

    if rec and rec.vars then
      info(
        "MSVC",
        require("features.maintenance.local_storage").path("state", "msvc_developer_environment.json"),
        ("%d variables and %d PATH directories, set inside Neovim only (%s)"):format(
          vim.tbl_count(rec.vars),
          #(rec.path or {}),
          rec.vs and rec.vs.name or "Visual Studio"
        )
      )
    end
  end

  items[#items + 1] = {
    group = "PATH and environment",
    label = "system",
    path = "",
    action = "info",
    note = WIN and "the registry, the system and user PATH are never written"
      or "shell profiles and the login environment are never written",
  }

  return items
end

local safe

---@return ManagedItem[]
function M.items()
  local items = {
    {
      group = "Neovim",
      label = "config",
      path = norm(vim.fn.stdpath("config")),
      action = "keep",
      note = "this configuration, a git checkout (lazy-lock.json included); never removed",
    },
  }

  -- data, state, log and cache; on Windows the first three are one directory, on Linux state and log are.
  local by_path = {}

  for _, kind in ipairs({ "data", "state", "log", "cache" }) do
    local path = norm(vim.fn.stdpath(kind))
    local seen = by_path[key(path)]

    if seen then
      seen.label = seen.label .. ", " .. kind
    else
      by_path[key(path)] = {
        group = "Neovim",
        label = kind,
        path = path,
        action = "remove",
        kind = "stdpath",
        children = true,
      }

      items[#items + 1] = by_path[key(path)]
    end
  end

  -- What a reset could not finish removing, renamed beside the directory it was.
  for _, item in ipairs(vim.list_slice(items, 2)) do
    local parent, base = vim.fs.dirname(item.path), vim.fs.basename(item.path)

    for name, kind in vim.fs.dir(parent) do
      if kind == "directory" and name:sub(1, #base + 7) == base .. ".reset-" and name:match("%.reset%-%d+$") then
        items[#items + 1] = {
          group = "Neovim",
          label = "left by a reset",
          path = norm(vim.fs.joinpath(parent, name)),
          action = "remove",
          kind = "stdpath",
        }
      end
    end
  end

  vim.list_extend(items, neovide_items())
  vim.list_extend(items, project_items())
  vim.list_extend(items, environment_items())

  -- What the guard below refuses is listed as kept, with the reason.
  for _, item in ipairs(items) do
    local ok, why = true, nil

    if item.action == "remove" then
      ok, why = safe(item)
    end

    if not ok then
      item.action, item.note = "keep", "not removed: " .. why
    end
  end

  return items
end

-- Never anything that holds the configuration, the home directory or a drive root, and only what the item
-- kind names: Neovim's own directories (named after NVIM_APPNAME), Neovide's settings file, a database.
function safe(item)
  local path = item.path
  local home = uv.os_homedir() or ""
  local app = vim.fs.basename(vim.env.NVIM_APPNAME and vim.env.NVIM_APPNAME ~= "" and vim.env.NVIM_APPNAME or "nvim")
  local base = vim.fs.basename(path)

  if path == "" or not vim.startswith(path, "/") and not path:match("^%a:/") then
    return false, "not an absolute path"
  end

  -- Compared as the system resolves them too: a link, a junction or an 8.3 name (NETRUN~1) is the same place.
  local function holds(inner)
    return within(inner, path) or within(uv.fs_realpath(inner) or inner, uv.fs_realpath(path) or path)
  end

  if holds(vim.fn.stdpath("config")) or (home ~= "" and holds(home)) or #path <= 3 then
    return false, "holds the configuration, the home directory or a drive"
  end

  if item.kind == "stdpath" then
    local config = vim.fn.stdpath("config")

    local function strictly_inside(inner, outer)
      return within(inner, outer) and key(inner) ~= key(outer)
    end

    -- Inside the configuration (a variable pointed into a checkout): what lies there is not the reset's to remove.
    if
      strictly_inside(path, config)
      or strictly_inside(uv.fs_realpath(path) or path, uv.fs_realpath(config) or config)
    then
      return false, "lies inside the configuration"
    end

    return vim.startswith(base, app), "not named after " .. app
  elseif item.kind == "neovide" then
    return base == "neovide-settings.json", "not Neovide's settings file"
  elseif item.kind == "project" then
    return base == "compile_commands.json", "not a compile_commands.json"
  elseif item.kind == "configuration" then
    local storage = require("features.maintenance.local_storage")
    local parent = key(vim.fs.dirname(path))

    for _, kind in ipairs(storage.KINDS) do
      local ok, dir = pcall(vim.fn.stdpath, kind)

      if
        ok
        and type(dir) == "string"
        and key(dir) == parent
        and (base == storage.NAME or storage.old_names(kind)[base])
      then
        return true, nil
      end
    end

    return false, "not this configuration's own directory, nor a file an older layout of it left"
  end

  return false, "not something the reset removes"
end

-- This configuration's own files only: its directory in each of Neovim's, and what an older layout left beside
-- them (lua/features/maintenance/local_storage.lua). Neovim's and the plugins' data stay.
---@return ManagedItem[]
function M.configuration_items()
  local storage = require("features.maintenance.local_storage")
  local items, seen = {}, {}

  for _, kind in ipairs(storage.KINDS) do
    local ok, dir = pcall(vim.fn.stdpath, kind)

    if ok and type(dir) == "string" then
      local names = { [storage.NAME] = "this configuration's own files" }

      for name, holds in pairs(storage.old_names(kind)) do
        names[name] = "left by an older layout: " .. holds
      end

      for name, note in pairs(names) do
        local path = norm(vim.fs.joinpath(dir, name))

        if not seen[key(path)] and exists(path) then
          seen[key(path)] = true
          items[#items + 1] = {
            group = "This configuration",
            label = kind .. "/" .. name,
            path = path,
            kind = "configuration",
            action = "remove",
            note = note,
          }
        end
      end
    end
  end

  table.sort(items, function(a, b)
    return a.path < b.path
  end)

  return items
end

-- The items a reset of the given scope works on: "configuration" (this configuration's own files) or everything.
function M.items_for(scope)
  return scope == "configuration" and M.configuration_items() or M.items()
end

-- What a reset would remove.
---@param items? ManagedItem[]
function M.removable(items)
  return vim.tbl_filter(function(item)
    return item.action == "remove" and exists(item.path) and (safe(item))
  end, items or M.items())
end

-- Bytes under path; links are counted, not followed. step() runs between entries so a caller can yield.
local function bytes_under(path, step)
  local st = uv.fs_lstat(path)

  if not st or st.type ~= "directory" then
    return st and st.size or 0
  end

  local total, stack = 0, { path }

  while #stack > 0 do
    local dir = table.remove(stack)
    local fs = uv.fs_scandir(dir)

    while fs do
      local name, kind = uv.fs_scandir_next(fs)

      if not name then
        break
      end

      local child = dir .. "/" .. name

      if kind == "directory" then
        stack[#stack + 1] = child
      else
        local cst = uv.fs_lstat(child)

        total = total + (cst and cst.size or 0)
      end

      if step then
        step()
      end
    end
  end

  return total
end

local function human(n)
  if not n then
    return "..."
  end

  local units, i = { "B", "KB", "MB", "GB", "TB" }, 1

  while n >= 1024 and i < #units do
    n, i = n / 1024, i + 1
  end

  return i == 1 and ("%d B"):format(n) or ("%.1f %s"):format(n, units[i])
end

-- Entries directly under a directory: directories first, then files, each by name.
local function children_of(path)
  local list = {}

  for name, kind in vim.fs.dir(path) do
    list[#list + 1] = { name = name, kind = kind, path = vim.fs.joinpath(path, name) }
  end

  table.sort(list, function(a, b)
    if (a.kind == "directory") ~= (b.kind == "directory") then
      return a.kind == "directory"
    end

    return a.name:lower() < b.name:lower()
  end)

  return list
end

---@class ManagedView
---@field items ManagedItem[]
---@field children table<ManagedItem, table[]>
---@field sizes table<string, integer>  by path

---@param items? ManagedItem[]
---@return ManagedView
function M.view(items)
  local view = { items = items or M.items(), children = {}, sizes = {} }

  for _, item in ipairs(view.items) do
    if item.children and exists(item.path) then
      view.children[item] = children_of(item.path)
    end
  end

  return view
end

-- Every size the view shows, measured: what each line totals.
local function size_jobs(view)
  local jobs = {}

  for _, item in ipairs(view.items) do
    if item.action == "remove" and exists(item.path) then
      for _, child in ipairs(view.children[item] or {}) do
        jobs[#jobs + 1] = child.path
      end

      if not view.children[item] then
        jobs[#jobs + 1] = item.path
      end
    end
  end

  return jobs
end

local function item_size(view, item)
  local kids = view.children[item]

  if not kids then
    return view.sizes[item.path]
  end

  local total = 0

  for _, child in ipairs(kids) do
    if not view.sizes[child.path] then
      return nil
    end

    total = total + view.sizes[child.path]
  end

  return total
end

-- Measures every size now (a shell has nothing else to do).
function M.measure(view)
  for _, path in ipairs(size_jobs(view)) do
    view.sizes[path] = bytes_under(path)
  end
end

-- Measures in slices of about 4 ms, calling on_change after each finished entry, until cancelled() says stop.
function M.measure_async(view, on_change, cancelled)
  local jobs = size_jobs(view)
  local co = coroutine.create(function()
    local slice = uv.hrtime()

    local function step()
      if uv.hrtime() - slice > 4e6 then
        coroutine.yield()
        slice = uv.hrtime()
      end
    end

    for _, path in ipairs(jobs) do
      view.sizes[path] = bytes_under(path, step)
      on_change()
    end
  end)

  local function resume()
    if cancelled() then
      return
    end

    local ok = coroutine.resume(co)

    if ok and coroutine.status(co) ~= "dead" then
      vim.defer_fn(resume, 10)
    end
  end

  resume()
end

local TAG = { remove = "remove", keep = "keep", info = "" }

-- The view as text: lines, the path each line stands for, and highlight spans { line, col, end_col, group }.
function M.render(view, opts)
  opts = opts or {}

  local lines, targets, marks = {}, {}, {}
  local group

  local function add(text, target, spans)
    lines[#lines + 1] = text
    targets[#lines] = target

    for _, s in ipairs(spans or {}) do
      marks[#marks + 1] = { #lines - 1, s[1], s[2], s[3] }
    end
  end

  local app = vim.env.NVIM_APPNAME and vim.env.NVIM_APPNAME ~= "" and vim.env.NVIM_APPNAME or "nvim"

  local system = WIN and "Windows" or MAC and "macOS" or vim.uv.os_uname().sysname

  add(("Managed paths (%s, NVIM_APPNAME=%s)"):format(system, app), nil, { { 0, -1, "Title" } })

  if opts.hint ~= false then
    add("<CR> open   y copy the path   q close", nil, { { 0, -1, "Comment" } })
  end

  local report = M.report_file()

  if exists(report) then
    local ok, text = pcall(vim.fn.readfile, report, "", 1)

    add(("Last reset: %s (%s)"):format(ok and text[1] or "?", M.display(report)), report, { { 0, -1, "Comment" } })
  end

  add("")
  add("Layout", nil, { { 0, -1, "Title" } })

  local layout = M.environment()

  if #layout == 0 then
    add("  the defaults: no NVIM_APPNAME, no XDG_*_HOME, no sandbox", nil, { { 0, -1, "Comment" } })
  end

  for _, e in ipairs(layout) do
    local head = ("  %-18s %s"):format(e.name, e.value)

    add(head .. "  " .. e.note, nil, { { 2, 2 + #e.name, "Identifier" }, { #head, -1, "Comment" } })
  end

  for _, item in ipairs(view.items) do
    if item.group ~= group then
      group = item.group
      add("")
      add(group, nil, { { 0, -1, "Title" } })
    end

    local tag = TAG[item.action]
    local present = item.path == "" or exists(item.path)
    local size = item.action == "remove" and present and human(item_size(view, item)) or ""
    local head = ("  %-6s  %-18s "):format(tag, item.label)
    local path = item.path ~= "" and M.display(item.path) or ""
    local text = head .. path

    if not present then
      text = text .. "  (absent)"
    end

    if size ~= "" then
      text = text .. "  " .. size
    end

    if item.note then
      text = text .. "  " .. item.note
    end

    local tag_hl = item.action == "remove" and "DiagnosticWarn" or item.action == "keep" and "DiagnosticOk" or "Comment"

    add(text, item.path ~= "" and item.path or nil, {
      { 2, 2 + #tag, tag_hl },
      { #head + #path, -1, "Comment" },
    })

    for _, child in ipairs(view.children[item] or {}) do
      local name = child.name .. (child.kind == "directory" and "/" or "")
      local note = KNOWN[child.name] or ((child.name == "log" or child.name:match("%.log$")) and "a log" or "")
      local line = ("            %-24s %10s  %s"):format(name, human(view.sizes[child.path]), note)
      local name_hl = child.kind == "directory" and "Directory" or "Normal"

      add(line, child.path, { { 12, 12 + #name, name_hl }, { 37, -1, "Comment" } })
    end
  end

  add("")
  add("Reset", nil, { { 0, -1, "Title" } })
  add('  :ManagedPathsReset (no key) asks for "reset" to be typed, quits Neovim and removes every "remove"')
  add("  line once it has exited. From a terminal, with every Neovim closed, the same question:")
  add(("  nvim -l %s"):format(M.display(M.script())))
  add("  The next start installs the plugins, Mason's packages and the parsers again.")

  return lines, targets, marks
end

function M.script()
  return vim.fs.joinpath(vim.fn.stdpath("config"), "scripts", "reset_to_fresh_clone.lua")
end

function M.report_file()
  return require("features.maintenance.local_storage").path("state", "reset_report.txt")
end

-- Other running Neovims of this configuration: those with a UI record themselves
-- (lua/features/editing/open_in_running_instance.lua); one started headless is not seen.
---@param ignore? integer[]
function M.other_instances(ignore)
  local skip = { [uv.os_getpid()] = true }

  for _, pid in ipairs(ignore or {}) do
    skip[pid] = true
  end

  local ok, ro = pcall(require, "features.editing.open_in_running_instance")
  local dir = ok and ro.focus_dir and ro.focus_dir()
  local found = {}

  if not dir then
    return found
  end

  for name in vim.fs.dir(dir) do
    local pid = tonumber(name)

    if pid and not skip[pid] and uv.kill(pid, 0) == 0 then
      found[#found + 1] = pid
    end
  end

  return found
end

-- Removes one item. A directory is first renamed beside itself: Windows refuses that while any file in it is open (a
-- running clangd, the windows_ime_helper watcher, a swap file), and the directory stays whole instead of half gone.
local function remove_one(item)
  local path = item.path
  local st = uv.fs_lstat(path)

  if not st then
    return true, "already absent"
  end

  local ok, why = safe(item)

  if not ok then
    return false, "refused: " .. why
  end

  if st.type ~= "directory" then
    local done, err = uv.fs_unlink(path)

    return done ~= nil, err
  end

  local trash = ("%s.reset-%d"):format(path, uv.os_getpid())
  local moved, err = uv.fs_rename(path, trash)

  if not moved then
    return false, "in use, left as it was (" .. tostring(err) .. ")"
  end

  local removed, rm_err = pcall(vim.fs.rm, trash, { recursive = true, force = true })

  if not removed or exists(trash) then
    return false, ("moved to %s, not all of it could be removed: %s"):format(M.display(trash), tostring(rm_err))
  end

  return true
end

-- Removes what M.removable() lists; returns { item, ok, why } per item.
function M.remove(items)
  local results = {}

  for _, item in ipairs(M.removable(items)) do
    local ok, why = remove_one(item)

    results[#results + 1] = { item = item, ok = ok, why = why }
  end

  return results
end

function M.summary(results)
  local lines = {}
  local failed = 0

  for _, r in ipairs(results) do
    failed = failed + (r.ok and 0 or 1)
    lines[#lines + 1] = ("%s  %s%s"):format(
      r.ok and "removed" or "KEPT   ",
      M.display(r.item.path),
      r.why and ("  (" .. r.why .. ")") or ""
    )
  end

  local head = failed == 0 and ("%d removed"):format(#results)
    or ("%d removed, %d kept: close every Neovim and Neovide, then nvim -l scripts/reset_to_fresh_clone.lua in a terminal"):format(
      #results - failed,
      failed
    )

  return os.date("%Y-%m-%d %H:%M ") .. head, lines
end

local view_win

-- :ManagedPaths: the list in a float; sizes fill in as they are measured.
function M.show()
  if view_win and view_win:valid() then
    view_win:close()
  end

  local view = M.view()
  local ns = vim.api.nvim_create_namespace("managed_paths")
  local targets = {}
  local win

  local function paint()
    if not (win and win:buf_valid()) then
      return
    end

    local lines, t, marks = M.render(view)

    targets = t
    vim.bo[win.buf].modifiable = true
    vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, lines)
    vim.bo[win.buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(win.buf, ns, 0, -1)
    for _, m in ipairs(marks) do
      local len = #lines[m[1] + 1]

      pcall(vim.api.nvim_buf_set_extmark, win.buf, ns, m[1], math.min(m[2], len), {
        end_col = m[3] < 0 and len or math.min(m[3], len),
        hl_group = m[4],
      })
    end
  end

  local function target()
    return targets[vim.api.nvim_win_get_cursor(0)[1]]
  end

  win = Snacks.win({
    title = " Managed paths ",
    border = "rounded",
    width = 0.9,
    height = 0.85,
    ft = "managedpaths",
    bo = { modifiable = false },
    wo = { wrap = false, cursorline = true, spell = false, conceallevel = 0 },
    keys = {
      q = "close",
      ["<CR>"] = {
        "<CR>",
        function(self)
          local path = target()

          if path then
            self:close()
            vim.cmd.edit(vim.fn.fnameescape(path))
          end
        end,
        desc = "Open",
      },
      y = {
        "y",
        function()
          local path = target()

          if path then
            vim.fn.setreg("+", M.display(path))
            vim.notify("Copied " .. M.display(path), vim.log.levels.INFO, { title = "Managed paths" })
          end
        end,
        desc = "Copy path",
      },
    },
  })

  view_win = win
  paint()

  M.measure_async(view, paint, function()
    return not win:buf_valid()
  end)
end

-- The confirmation the removing process needs: written only after "reset" was typed at the prompt, read once.
local function token_file()
  return require("features.maintenance.local_storage").path("state", "reset_confirmation")
end

-- For scripts/reset_to_fresh_clone.lua: whether token is the one :ManagedPathsReset wrote within ten minutes. Used up
-- either way.
function M.consume_token(token)
  local file = token_file()
  local ok, lines = pcall(vim.fn.readfile, file)

  os.remove(file)

  local at = ok and tonumber(lines[2] or "")

  return token ~= nil and ok and lines[1] == token and at ~= nil and os.time() - at < 600
end

-- What is typed at the prompt, nothing else: keys already waiting (a mapping, a macro, typeahead) are set
-- aside until it closes, there is no default and no completion, and the answer leaves no history to recall.
function M.typed(prompt)
  vim.fn.inputsave()

  local ok, answer = pcall(vim.fn.input, { prompt = prompt, cancelreturn = "" })

  vim.fn.inputrestore()
  pcall(vim.fn.histdel, "input", [[^\s*reset\s*$]])

  return ok and answer or ""
end

-- :ManagedPathsReset: after "reset" is typed, quits Neovim (asking about unsaved buffers as :confirm qa does)
-- and removes what is marked once this Neovim, and the Neovide around it, have exited.
function M.reset(scope)
  scope = scope == "configuration" and "configuration" or "all"

  local items = M.items_for(scope)
  local doomed = M.removable(items)

  if #doomed == 0 then
    return vim.notify("Nothing to remove", vim.log.levels.INFO, { title = "Managed paths" })
  end

  local others = M.other_instances()

  if #others > 0 then
    return vim.notify(
      ("Close the other Neovim instances first (PID %s): their files are among these."):format(
        table.concat(others, ", ")
      ),
      vim.log.levels.ERROR,
      { title = "Managed paths" }
    )
  end

  if scope == "configuration" then
    vim.notify("This configuration's own files to remove:\n" .. table.concat(
      vim.tbl_map(function(item)
        return "  " .. M.display(item.path) .. "  (" .. item.note .. ")"
      end, doomed),
      "\n"
    ), vim.log.levels.WARN, { title = "Managed paths" })
  else
    M.show()
  end

  -- The window draws before the prompt takes the keyboard.
  vim.cmd.redraw()

  local answer = M.typed(
    scope == "configuration"
        and ('Type "reset" to quit Neovim and remove this configuration\'s %d directories and files: '):format(#doomed)
      or ('Type "reset" to quit Neovim and remove the %d "remove" lines: '):format(#doomed)
  )

  if answer ~= "reset" then
    return vim.notify("Reset cancelled: nothing was removed", vim.log.levels.INFO, { title = "Managed paths" })
  end

  local wait = { uv.os_getpid() }

  -- Neovide writes its window state as it closes, after this Neovim.
  if vim.g.neovide then
    wait[#wait + 1] = uv.os_getppid()
  end

  local token = vim.fn.sha256(("%d:%d:%s"):format(uv.os_getpid(), uv.hrtime(), tostring({})))

  vim.fn.mkdir(vim.fs.dirname(token_file()), "p")
  vim.fn.writefile({ token, tostring(os.time()) }, token_file())

  local au = vim.api.nvim_create_autocmd("VimLeave", {
    once = true,
    callback = function()
      -- Detached, no stdio and out of libuv's kill-on-exit job (Windows): it outlives this Neovim.
      ---@diagnostic disable-next-line: missing-fields, missing-parameter
      local handle = uv.spawn(vim.v.progpath, {
        args = { "-l", M.script(), "--after", table.concat(wait, ","), "--token", token, "--scope", scope },
        detached = true,
        hide = true,
        stdio = {},
      })

      if handle then
        handle:unref()
      end
    end,
  })

  pcall(vim.api.nvim_command, "confirm qa")

  -- Still here: quitting was cancelled, and the confirmation with it.
  pcall(vim.api.nvim_del_autocmd, au)
  os.remove(token_file())
  vim.notify("Reset cancelled: Neovim did not quit", vim.log.levels.WARN, { title = "Managed paths" })
end

-- After a reset Neovim starts as a fresh clone; config/lazy.lua calls this as it installs lazy.nvim again.
function M.announce_report()
  local report = M.report_file()
  local ok, lines = pcall(vim.fn.readfile, report)

  if not ok or #lines == 0 then
    return
  end

  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    once = true,
    callback = function()
      vim.schedule(function()
        vim.notify(
          "Reset " .. table.concat(lines, "\n"),
          lines[1]:find("kept") and vim.log.levels.WARN or vim.log.levels.INFO,
          { title = "Managed paths" }
        )
      end)
    end,
  })
end

return M
