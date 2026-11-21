-- :checkhealth features.util: where everything is kept, programs registered by path, Discord Rich Presence and the
-- Windows platform code.
local status = require("features.util.feature_status")

local M = {}

-- Programs registered by path (<leader>uX, :ToolPath); nothing is reported when none is.
local function registered_programs()
  local programs = require("features.util.tool_paths")
  local registered, unreadable = programs.read()

  if not registered then
    status.blocked("Programs registered by path (<leader>uX)", unreadable, {
      "nothing is registered, unregistered or put on PATH until it is fixed or removed",
    })

    return
  elseif next(registered) == nil then
    status.available("Programs registered by path (<leader>uX)", "none registered")

    return
  end

  for name, target in pairs(registered) do
    local found = vim.fn.exepath(name)
    local usable, why = programs.check(name, target)

    found = found ~= "" and vim.fs.normalize(found) or ""
    if not usable then
      status.blocked(name, why, { ":ToolPath " .. name .. " to point it elsewhere" })
    elseif found == "" then
      status.blocked(name, ("registered as %s, but its shim is missing"):format(target), { "restart Neovim" })
    elseif not vim.startswith(found:lower(), vim.fs.normalize(programs.SHIMS):lower()) then
      status.blocked(name, ("registered as %s, but PATH has %s first"):format(target, found))
    else
      status.available(name, target)
    end
  end
end

local function managed_paths()
  local paths = require("features.util.managed_paths")

  status.available("Where everything is kept (:ManagedPaths, <leader>uM)", #paths.items() .. " places")

  if vim.uv.fs_stat(paths.script()) then
    status.available("Back to a fresh clone (:ManagedPathsReset, typed confirmation)", paths.script())
  else
    status.blocked("Back to a fresh clone (:ManagedPathsReset)", paths.script() .. " is missing")
  end
end

local function program_discovery()
  if not status.WINDOWS then
    status.unsupported("Program discovery from the system's records", "it reads Windows' registry and App Paths")
  elseif require("features.util.tool_paths.windows_discovery").read() then
    status.available("Program discovery (<leader>uX)", "its last run's results are kept in stdpath('state')")
  else
    status.available("Program discovery (<leader>uX)", "not run yet; it runs on request only")
  end
end

local function discord()
  local supported, running, state = require("features.util.discord_rich_presence").status()

  if not supported then
    status.unsupported("Discord Rich Presence", "turned off for this system in its settings")
  elseif not running then
    status.available("Discord Rich Presence", "off (<leader>uP turns it on)")
  elseif state == "ready" then
    status.available("Discord Rich Presence", "connected")
  else
    status.blocked("Discord Rich Presence", "on, but not connected (" .. state .. "): is Discord running?")
  end
end

local function windows_platform()
  if not status.WINDOWS then
    status.unsupported("executable() memory and the IME helper", "they make up for what Windows lacks")

    return
  end

  if vim.fn.exepath == require("features.util.windows.executable_lookup_cache").exepath then
    status.available(
      "executable() and exepath() with a memory",
      "per PATH, in stdpath('cache')/nvim-config/executable_lookup_cache.json"
    )
  else
    status.blocked("executable() and exepath() with a memory", "not installed by init.lua")
  end

  local path, why = require("features.util.windows.ime_helper").path({ build = false })

  if path then
    status.available("windows_ime_helper (IME, indicators, window raise, shims)", path)
  else
    status.blocked("windows_ime_helper (IME, indicators, window raise, shims)", why, {
      "Visual Studio's cl, or clang targeting MSVC, on PATH builds native/windows_ime_helper.c in the background at startup",
    })
  end
end

-- Windows: folders this Neovim runs programs from (PATH's, and the registered programs') that broad groups may change:
-- Everyone, Authenticated Users (service accounts too), Users, INTERACTIVE. A program or DLL put there runs as this
-- user. Folders made directly under C:\ inherit such a grant (C:\Python314, C:\msys64). One PowerShell run, here only.
local ACL_SCRIPT = [[
$broad = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-4')
$changes = 0x2 -bor 0x4 -bor 0x40 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000
foreach ($path in ($env:NVIM_ACL_PATHS -split "`n")) {
  if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }
  try { $acl = Get-Acl -LiteralPath $path } catch { continue }
  foreach ($ace in $acl.Access) {
    if ($ace.AccessControlType -ne 'Allow' -or ($ace.PropagationFlags -band 2)) { continue }
    try { $sid = $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { continue }
    if (($broad -contains $sid) -and (([int64]$ace.FileSystemRights -band $changes) -ne 0)) {
      "$path`t$($ace.IdentityReference)"
      break
    }
  }
}
]]

local function changeable_folders()
  if not status.WINDOWS then
    status.unsupported("Folders checked for other accounts' write access", "a Windows ACL check")

    return
  end

  local dirs, seen = {}, {}

  local function add(dir)
    dir = dir and vim.fs.normalize(dir) or ""

    if dir ~= "" and not seen[dir:lower()] then
      seen[dir:lower()] = true
      dirs[#dirs + 1] = dir
    end
  end

  for _, dir in ipairs(require("features.util.path_variable").directories(vim.env.PATH)) do
    add(dir)
  end

  for _, target in pairs(require("features.util.tool_paths").read() or {}) do
    if type(target) == "string" then
      add(vim.fs.dirname(target))
    end
  end

  local res = vim
    .system({ "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ACL_SCRIPT }, {
      text = true,
      env = { NVIM_ACL_PATHS = table.concat(dirs, "\n") },
    })
    :wait(30000)

  if res.code ~= 0 then
    vim.health.warn("Could not read the folders' permissions: " .. vim.trim(res.stderr or ""))

    return
  end

  local found = 0

  for line in vim.gsplit(res.stdout or "", "\r?\n", { trimempty = true }) do
    local dir, who = line:match("^(.-)\t(.+)$")

    if dir then
      found = found + 1
      vim.health.warn(("%s: %s may change it, so a program or DLL put there runs as you"):format(dir, who), {
        "An administrator can take that right away and give it to your account instead, e.g. "
          .. ('icacls "%s" /inheritance:d /remove:g *S-1-5-11 /grant:r "%%USERNAME%%":(OI)(CI)M /T'):format(dir),
      })
    end
  end

  if found == 0 then
    vim.health.ok(("No folder Neovim runs programs from may be changed by other accounts (%d checked)"):format(#dirs))
  end
end

function M.check()
  vim.health.start("Managed paths")
  managed_paths()
  vim.health.start("Programs registered by path")
  registered_programs()
  program_discovery()
  vim.health.start("Discord Rich Presence")
  discord()
  vim.health.start("Windows platform")
  windows_platform()
  vim.health.start("Folders other accounts may change (Windows)")
  changeable_folders()
end

return M
