-- Where Neovim keeps its files, checked against the rule it follows, and lua/features/maintenance/stored_data_paths.lua
-- checked against both. Run by tests/stored_data_paths/run.sh (Linux, macOS, the containers of
-- tests/stored_data_paths/docker.sh) and run.ps1 (Windows), each variant in a throwaway root: PATHS_TEST_ROOT names it,
-- and nothing outside it is ever removed.
--
--   PATHS_TEST_MODE=layout  stdpath() against the rule. Any Neovim from 0.5 on (a distribution's own package):
--                           the question is whether that build keeps the rule.
--   PATHS_TEST_MODE=module  also the module: what it lists, what it says decided the layout, and what a reset
--                           removes and keeps. Neovim 0.11 or later, as the configuration needs.
--
-- The rule, on Linux and macOS: $XDG_CONFIG_HOME, $XDG_DATA_HOME, $XDG_STATE_HOME, $XDG_CACHE_HOME, else
-- ~/.config, ~/.local/share, ~/.local/state, ~/.cache, each with NVIM_APPNAME (else nvim) appended; the log in
-- the state directory. On Windows the same variables, else %LOCALAPPDATA% (config, data, state) and %TEMP%
-- (cache), with "-data" after the name for data and state.
local MODE = os.getenv("PATHS_TEST_MODE") or "layout"
local ROOT = os.getenv("PATHS_TEST_ROOT")
local VARIANT = os.getenv("PATHS_TEST_VARIANT") or "?"
local uv = vim.uv or vim.loop
local WIN = vim.fn.has("win32") == 1
local MAC = vim.fn.has("mac") == 1
local failures = 0

local function say(kind, text)
  io.stdout:write(("%-4s [%s] %s\n"):format(kind, VARIANT, text))
end

-- Both return true, so `ok and pass(...) or fail(...)` reports one of them.
local function pass(text)
  say("PASS", text)

  return true
end

local function fail(text)
  failures = failures + 1
  say("FAIL", text)

  return true
end

local function finish()
  io.stdout:flush()
  vim.cmd(failures == 0 and "qall!" or ("cquit " .. math.min(failures, 255)))
end

local function env(name)
  local value = os.getenv(name)

  return value ~= nil and value ~= "" and value or nil
end

local function norm(path)
  path = (path or ""):gsub("\\", "/"):gsub("/+$", "")

  return WIN and path:lower() or path
end

local function join(...)
  return table.concat({ ... }, "/")
end

local function under(path, root)
  path, root = norm(path), norm(root)

  return path == root or path:sub(1, #root + 1) == root .. "/"
end

-- Never against a real home: HOME (USERPROFILE on Windows) must lie inside the throwaway root.
local home = WIN and env("USERPROFILE") or env("HOME")

if not ROOT or not home or not under(home, ROOT) then
  fail("PATHS_TEST_ROOT unset or HOME outside it: refusing to run (use tests/stored_data_paths/run.sh or run.ps1)")

  return finish()
end

local app = env("NVIM_APPNAME") or "nvim"
local expected

if WIN then
  local la, temp = env("LOCALAPPDATA"), env("TEMP")

  expected = {
    config = join(env("XDG_CONFIG_HOME") or la, app),
    data = join(env("XDG_DATA_HOME") or la, app .. "-data"),
    state = join(env("XDG_STATE_HOME") or la, app .. "-data"),
    cache = join(env("XDG_CACHE_HOME") or temp, app),
  }
else
  expected = {
    config = join(env("XDG_CONFIG_HOME") or join(home, ".config"), app),
    data = join(env("XDG_DATA_HOME") or join(home, ".local", "share"), app),
    state = join(env("XDG_STATE_HOME") or join(home, ".local", "state"), app),
    cache = join(env("XDG_CACHE_HOME") or join(home, ".cache"), app),
  }
end

expected.log = expected.state

local version = vim.fn.execute("version"):match("NVIM v[^\r\n]+") or "?"

say("INFO", ("%s, %s"):format(version, WIN and "Windows" or MAC and "macOS" or "Linux"))

for _, kind in ipairs({ "config", "data", "state", "cache", "log" }) do
  local ok, got = pcall(vim.fn.stdpath, kind)

  if not ok then
    say("SKIP", ("stdpath(%q): not in this Neovim"):format(kind))
  elseif norm(got) == norm(expected[kind]) then
    pass(("stdpath(%q) = %s"):format(kind, got))
  else
    fail(("stdpath(%q) = %s, the rule says %s"):format(kind, got, expected[kind]))
  end
end

if MODE ~= "module" then
  return finish()
end

if not (vim.fs and vim.fs.rm and vim.fs.joinpath and vim.uv) then
  say("SKIP", "module: needs Neovim 0.11 or later, as the configuration does")

  return finish()
end

local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, "S").source:sub(2)))))

package.path = vim.fs.joinpath(repo, "lua", "?.lua") .. ";" .. package.path

local mp = require("features.maintenance.stored_data_paths")

local function touch(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")

  local f = assert(io.open(path, "w"))

  f:write("x")
  f:close()
end

local function exists(path)
  return uv.fs_lstat(path) ~= nil
end

-- The configuration's own files stay as they are: in the installed variant they are the real ones.
local function touch_if_absent(path)
  if not exists(path) then
    touch(path)
  end
end

-- What a Neovim of this configuration leaves, and what must survive a reset.
local holds_config = {}

for _, kind in ipairs({ "data", "state", "cache" }) do
  holds_config[kind] = under(expected.config, expected[kind])
end

touch_if_absent(join(expected.config, "init.lua"))
touch(join(expected.data, "lazy", "plugin", "init.lua"))
touch(join(expected.state, "shada", "main.shada"))
touch(join(expected.cache, "luac", "module"))

local outside = join(ROOT, "outside")

touch(join(outside, "precious.txt"))

-- A link inside the data directory to a directory outside it: the reset removes the link, never what it names.
local link = join(expected.data, "linked-outside")

if not holds_config.data then
  uv.fs_symlink(outside, link, WIN and { junction = true } or nil)
end

-- Neovide: its settings linked to the configuration as the README installs them, and its window state.
local neovide = mp.neovide_paths()

local neovide_config = assert(neovide.config, "no Neovide settings directory: HOME or APPDATA unset")
local neovide_data = assert(neovide.data, "no Neovide data directory: HOME or LOCALAPPDATA unset")

touch_if_absent(join(expected.config, "neovide", "config.toml"))
vim.fn.mkdir(vim.fs.dirname(neovide_config), "p")
if not exists(neovide_config) then
  uv.fs_symlink(join(expected.config, "neovide"), neovide_config, WIN and { junction = true } or nil)
end

touch(join(neovide_data, "neovide-settings.json"))

local expected_neovide_data = WIN and join(env("LOCALAPPDATA"), "neovide")
  or MAC and join(home, "Library", "Application Support", "neovide")
  or join(env("XDG_DATA_HOME") or join(home, ".local", "share"), "neovide")

if norm(neovide_data) == norm(expected_neovide_data) then
  pass("Neovide's window state: " .. neovide_data)
else
  fail(("Neovide's window state: %s, Neovide's source says %s"):format(neovide_data, expected_neovide_data))
end

local items = mp.items()
local listed = {}

for _, item in ipairs(items) do
  if item.group == "Neovim" then
    listed[norm(item.path)] = item
  end
end

local function check_item(kind, want_action)
  local item = listed[norm(expected[kind])]

  if not item then
    return fail(("%s: %s not listed"):format(kind, expected[kind]))
  end

  if item.action ~= want_action then
    return fail(("%s: %s listed as %s, expected %s (%s)"):format(kind, item.path, item.action, want_action, item.note))
  end

  pass(("%s listed as %s: %s"):format(kind, want_action, item.path))
end

check_item("config", "keep")
for _, kind in ipairs({ "data", "state", "cache" }) do
  check_item(kind, holds_config[kind] and "keep" or "remove")
end

local distinct = {}

for _, kind in ipairs({ "config", "data", "state", "cache" }) do
  distinct[norm(expected[kind])] = true
end

for path in pairs(listed) do
  if not distinct[path] then
    fail("listed but not one of Neovim's directories: " .. path)
  end
end

-- What decided the layout.
local seen = {}

for _, e in ipairs(mp.environment()) do
  seen[e.name] = e.value
end

for _, var in ipairs({ "NVIM_APPNAME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME" }) do
  if env(var) and seen[var] ~= env(var) then
    fail(("%s is set but not reported as deciding the layout"):format(var))
  elseif not env(var) and seen[var] then
    fail(("%s reported though unset"):format(var))
  end
end

if env("FLATPAK_ID") then
  if seen.Flatpak then
    pass("Flatpak sandbox recognised: " .. seen.Flatpak)
  else
    fail("FLATPAK_ID is set but no Flatpak sandbox is reported")
  end
end

pass(("layout reported as: %s"):format(next(seen) and table.concat(vim.tbl_keys(seen), ", ") or "the defaults"))

-- The reset of this configuration's own files: its directories and what an older layout left go; Neovim's and the
-- plugins' data stay.
local storage = require("features.maintenance.local_storage")

touch(storage.path("state", "registered_programs.json"))
touch(storage.path("cache", "executable_lookup_cache.json"))
touch(join(expected.state, "tools.json"))

local own = mp.configuration_items()

for _, item in ipairs(mp.removable(own)) do
  if not under(item.path, ROOT) then
    fail("the configuration's reset would remove outside the test root, stopping here: " .. item.path)

    return finish()
  end
end

for _, r in ipairs(mp.remove(own)) do
  if not r.ok then
    fail(("configuration's reset: not removed: %s (%s)"):format(r.item.path, tostring(r.why)))
  end
end

local own_gone = not exists(join(expected.state, storage.NAME))
  and not exists(join(expected.cache, storage.NAME))
  and not exists(join(expected.state, "tools.json"))

if own_gone then
  pass("the configuration's reset removed its own directories and the older layout's file")
else
  fail("the configuration's reset left its own files behind")
end

if exists(join(expected.data, "lazy", "plugin", "init.lua")) and exists(join(expected.config, "init.lua")) then
  pass("the configuration's reset kept the plugins' data and the configuration")
else
  fail("the configuration's reset removed more than its own files")
end

-- Nothing the reset would remove lies outside the throwaway root.
for _, item in ipairs(mp.removable(items)) do
  if not under(item.path, ROOT) then
    fail("would remove outside the test root, stopping here: " .. item.path)

    return finish()
  end
end

local results = mp.remove(items)

for _, r in ipairs(results) do
  if not r.ok then
    fail(("not removed: %s (%s)"):format(r.item.path, tostring(r.why)))
  end
end

local function gone(kind)
  local path = expected[kind]

  if holds_config[kind] then
    return exists(path) and pass(kind .. " kept: it holds the configuration")
      or fail(kind .. " removed though it holds the configuration")
  end

  return not exists(path) and pass(kind .. " removed") or fail(kind .. " still there: " .. path)
end

gone("data")
gone("state")
gone("cache")

local function expect(ok, yes, no)
  if ok then
    pass(yes)
  else
    fail(no)
  end
end

expect(exists(join(expected.config, "init.lua")), "configuration kept", "configuration removed: " .. expected.config)
expect(exists(join(outside, "precious.txt")), "a directory a link pointed to is kept", "a link's target was removed")
expect(not exists(join(neovide_data, "neovide-settings.json")), "Neovide's window state removed", "window state kept")
expect(exists(neovide_config), "Neovide's settings link kept", "Neovide's settings link removed")

finish()
