-- :checkhealth features.external_programs: the Mason packages the configuration asks for, the programs registered by
-- path, and what Windows' own records show.
local status = require("features.feature_status")

local M = {}

local function mason_packages()
  local ok, registry = pcall(require, "mason-registry")

  if not ok then
    status.blocked("Mason packages", "mason.nvim does not load")

    return
  end

  local runtimes = require("features.external_programs.package_runtime_requirements")
  local gate = status.WINDOWS and require("features.external_programs.mason_windows_install_gate") or nil
  local failures = gate and gate.failures() or {}
  local installed = {}

  for _, name in ipairs(LazyVim.opts("mason.nvim").ensure_installed or {}) do
    local found, pkg = pcall(registry.get_package, name)

    if not found then
      status.blocked(name, "not in the Mason registry")
    elseif pkg:is_installed() then
      local kind = ((pkg.spec.source or {}).id or ""):match("^pkg:(%w+)/")
      local need = runtimes.package[name] or runtimes.source[kind]

      if need and not status.find(need) then
        status.blocked(name, ("installed, but %s is missing"):format(status.label(need)))
      else
        installed[#installed + 1] = name
      end
    else
      local need = gate and gate.missing_runtime(name)
      local at = gate and gate.held_back(name, failures)
      local installable, can = pcall(pkg.is_installable, pkg)

      if installable and not can then
        status.unsupported(name, "no Mason build for " .. vim.uv.os_uname().machine)
      elseif need then
        status.blocked(name, ("not installed until %s is on PATH"):format(status.label(need)))
      elseif gate and at then
        status.blocked(
          name,
          ("install failed on %s; Mason retries it from %s"):format(
            os.date("%Y-%m-%d", at),
            os.date("%Y-%m-%d", at + gate.RETRY_DAYS * 86400)
          ),
          { ":MasonInstall " .. name .. " retries now", "mason.log in stdpath('log') has the error" }
        )
      else
        status.blocked(name, "not installed", { ":MasonInstall " .. name, ":checkhealth mason lists the installers" })
      end
    end
  end

  if #installed > 0 then
    status.available(("%d installed"):format(#installed), table.concat(installed, ", "))
  end
end

-- Programs registered by path (<leader>uX, :ToolPath); nothing is reported when none is.
local function registered_programs()
  local programs = require("features.external_programs.registered_programs")
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

function M.check()
  vim.health.start("Mason packages")
  mason_packages()
  vim.health.start("Programs registered by path")
  registered_programs()

  if not status.WINDOWS then
    status.unsupported("Program discovery from the system's records", "it reads Windows' registry and App Paths")
  else
    local found = require("features.external_programs.windows_program_discovery").read()

    if found then
      status.available("Program discovery (<leader>uX)", "its last run's results are kept in stdpath('state')")
    else
      status.available("Program discovery (<leader>uX)", "not run yet; it runs on request only")
    end
  end
end

return M
