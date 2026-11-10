-- Windows: what Mason's ensure_installed holds back. A package whose runtime is missing waits for it; one whose install
-- failed waits RETRY_DAYS, so a build that cannot succeed here (an npm package compiling a native addon, say) does not
-- rerun in the background of every session, nor hold Neovim's exit while it is torn down. :MasonInstall retries at
-- once, and a success clears the record (stdpath("state")/nvim-config/mason_install_failures.json).
local M = {}

M.RETRY_DAYS = 7

local FILE = require("features.util.storage").path("state", "mason_install_failures.json")

-- The record, {} when absent; nil and why when unreadable (never written over then).
function M.failures()
  local _, _, absent = vim.uv.fs_stat(FILE)

  if absent == "ENOENT" then
    return {}
  end

  local ok, failures = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(FILE), "\n"))
  end)

  if ok and type(failures) == "table" then
    return failures
  end

  return nil, ("%s cannot be read (%s)"):format(FILE, ok and "not a JSON object" or tostring(failures))
end

local function save(failures)
  if next(failures) == nil then
    os.remove(FILE)
  else
    pcall(vim.fn.writefile, { vim.json.encode(failures) }, FILE)
  end
end

-- The runtimes name needs, when none of them is on PATH.
function M.missing_runtime(name)
  local need = require("features.lsp.mason.runtime_requirements").package[name]

  for _, runtime in ipairs(need or {}) do
    if vim.fn.executable(runtime) == 1 then
      return nil
    end
  end

  return need
end

-- When name last failed, while that still holds it back.
function M.held_back(name, failures)
  local at = (failures or M.failures() or {})[name]

  return type(at) == "number" and os.time() - at < M.RETRY_DAYS * 86400 and at or nil
end

-- Everything asked for, before filter(): the health check lists what the gate holds back too.
M.requested = nil

function M.filter(names)
  local failures = M.failures() or {}

  M.requested = vim.deepcopy(names)

  return vim.tbl_filter(function(name)
    return not M.missing_runtime(name) and not M.held_back(name, failures)
  end, names)
end

-- mason-lspconfig installs every configured server: a held-back one gets mason = false and comes from PATH.
function M.filter_servers(servers)
  local ok, map = pcall(function()
    return require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
  end)

  local failures = M.failures() or {}

  for name, server in pairs(servers) do
    -- Without the registry the map is empty; most servers share their package's name.
    local package = ok and map[name] or name
    local held = M.missing_runtime(package) or M.held_back(package, failures)

    if held and (server == true or type(server) == "table") then
      servers[name] = vim.tbl_extend("force", type(server) == "table" and server or {}, { mason = false })
    end
  end
end

local tracking = false

-- An install cut short by Neovim exiting is not a failure of the package.
function M.track()
  local ok, registry = pcall(require, "mason-registry")

  if tracking or not ok then
    return
  end

  tracking = true
  registry:on(
    "package:install:failed",
    vim.schedule_wrap(function(pkg, result)
      if vim.v.exiting ~= vim.NIL or tostring(result):find("aborted") then
        return
      end

      local failures, unreadable = M.failures()

      if not failures then
        return vim.notify(("%s; %s's failure is not recorded"):format(unreadable, pkg.name), vim.log.levels.WARN)
      end

      failures[pkg.name] = os.time()
      save(failures)
    end)
  )

  registry:on(
    "package:install:success",
    vim.schedule_wrap(function(pkg)
      local failures = M.failures()

      if failures and failures[pkg.name] then
        failures[pkg.name] = nil
        save(failures)
      end
    end)
  )
end

return M
