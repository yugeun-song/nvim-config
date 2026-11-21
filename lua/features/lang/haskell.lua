-- ghcup's bin directory, added at the end of PATH when Haskell is first needed (a Haskell buffer, :checkhealth):
-- ghcup installs there (https://www.haskell.org/ghcup/install/) without the environment Neovim started from always
-- knowing. GHCUP_INSTALL_BASE_PREFIX, ghcup's variable for its base, names it; else ~/.ghcup/bin. On Windows only that
-- variable, which ghcup's installer sets: any user may create C:\ghcup where ghcup is not installed.
local M = {}

local WIN = vim.fn.has("win32") == 1
local added = false

function M.bin_directory()
  local base = vim.env.GHCUP_INSTALL_BASE_PREFIX

  if base and base ~= "" then
    return vim.fs.joinpath(base, WIN and "ghcup" or ".ghcup", "bin")
  end

  return not WIN and vim.fs.joinpath(vim.uv.os_homedir() or "", ".ghcup", "bin") or nil
end

function M.add_to_path()
  if added then
    return
  end

  added = true

  local bin = M.bin_directory()

  if not bin or not vim.uv.fs_stat(bin) then
    return
  end

  local path_variable = require("features.util.path_variable")
  local wanted = vim.fs.normalize(bin, { expand_env = false })

  for _, dir in ipairs(path_variable.directories(vim.env.PATH)) do
    local have = vim.fs.normalize(dir, { expand_env = false })

    if (WIN and have:lower() == wanted:lower()) or have == wanted then
      return
    end
  end

  vim.env.PATH = path_variable.append(vim.env.PATH or "", bin)
end

local debugger_guarded = false

-- haskell-tools registers the Haskell debugger at each discovery as a server adapter that nvim-dap starts and ends:
-- hdb listening on 0.0.0.0 (it takes its address only from DAP_HOST), left running on Windows. Each time, the adapter
-- becomes one of lua/features/dap/managed_server.lua with the same program, on 127.0.0.1.
function M.guard_debugger()
  local ok, htdap = pcall(require, "haskell-tools.dap")

  if debugger_guarded or not ok or type(htdap.discover_configurations) ~= "function" then
    return
  end

  debugger_guarded = true

  local discover = htdap.discover_configurations

  ---@diagnostic disable-next-line: duplicate-set-field
  htdap.discover_configurations = function(...)
    local result = discover(...)
    local dap = package.loaded.dap
    local adapter = dap and dap.adapters["haskell-debugger"]

    if type(adapter) == "table" and adapter.type == "server" and type(adapter.executable) == "table" then
      local executable = adapter.executable

      dap.adapters["haskell-debugger"] = require("features.dap.managed_server").adapter({
        name = "the Haskell debugger",
        env = { DAP_HOST = "127.0.0.1" },
        cmd = function(port)
          local cmd = { executable.command }

          for _, arg in ipairs(executable.args or {}) do
            cmd[#cmd + 1] = (tostring(arg):gsub("%${port}", tostring(port)))
          end

          return cmd
        end,
      })
    end

    return result
  end
end

return M
