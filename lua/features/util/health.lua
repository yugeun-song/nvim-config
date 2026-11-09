-- :checkhealth features.util: where everything is kept, programs registered by path, Discord Rich Presence and the
-- Windows platform code.
local status = require("features.util.feature_status")

local M = {}

-- Programs registered by path (<leader>uX, :ToolPath); nothing is reported when none is.
local function registered_programs()
  local programs = require("features.util.tool_paths")
  local registered = programs.read()

  if next(registered) == nil then
    status.available("Programs registered by path (<leader>uX)", "none registered")

    return
  end

  for name, target in pairs(registered) do
    local found = vim.fn.exepath(name)

    found = found ~= "" and vim.fs.normalize(found) or ""
    if vim.fn.executable(target) ~= 1 then
      status.blocked(name, target .. " is gone", { ":ToolPath " .. name .. " to point it elsewhere" })
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
end

return M
