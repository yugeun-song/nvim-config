-- :checkhealth features.lsp: language servers and Mason packages. The servers are the ones the merged configuration enables, each checked
-- by the command Neovim would start it with.
local status = require("features.util.feature_status")

local M = {}

local function attach_rules()
  local path = require("features.lsp.attach_rules").registry_path()
  local _, err = require("features.lsp.attach_rules.path_and_file_helpers").read_json(path)

  if err then
    status.blocked("Attach rules (<leader>cL)", err, { "<leader>cLe edits it" })
  elseif not vim.uv.fs_stat(path) then
    status.available("Attach rules (<leader>cL)", "none written: every server attaches wherever it is configured")
  else
    status.available("Attach rules (<leader>cL)", path)
  end
end

local function servers()
  local configured = status.plugin_options("nvim-lspconfig").servers or {}

  -- Mason's bin joins PATH when Mason loads, and a server's definition (its cmd) comes with nvim-lspconfig and the
  -- configuration's setup of it: both load first, as they would for the first file.
  pcall(require("lazy").load, { plugins = { "mason.nvim", "nvim-lspconfig" } })

  local names = {}

  for name, server in pairs(configured) do
    if name ~= "*" and server ~= false and not (type(server) == "table" and server.enabled == false) then
      names[#names + 1] = name
    end
  end

  table.sort(names)
  for _, name in ipairs(names) do
    local config = vim.lsp.config[name]
    local cmd = config and config.cmd

    if type(cmd) == "function" then
      status.available("Server " .. name, "started through a function of its configuration")
    elseif type(cmd) == "table" and cmd[1] then
      if vim.fn.executable(cmd[1]) == 1 then
        status.available("Server " .. name, cmd[1])
      else
        status.blocked("Server " .. name, cmd[1] .. " is not on PATH", { ":MasonInstall, or install it yourself" })
      end
    else
      status.blocked("Server " .. name, "no command in its configuration")
    end
  end
end

local function mason_packages()
  local ok, registry = pcall(require, "mason-registry")

  if not ok then
    status.blocked("Mason packages", "mason.nvim does not load")

    return
  end

  -- Before the first download every package would read as missing from the registry.
  if #registry.get_all_package_names() == 0 then
    status.blocked(
      "Mason packages",
      "Mason's registry is not downloaded yet, so no package can be checked or installed",
      { ":MasonUpdate downloads it (it needs the network)" }
    )

    return
  end

  local runtimes = require("features.lsp.mason.runtime_requirements")
  local gate = status.WINDOWS and require("features.lsp.mason.windows_install_gate") or nil
  local recorded, unreadable

  if gate then
    recorded, unreadable = gate.failures()
  end

  local failures = recorded or {}
  local installed = {}

  if unreadable then
    status.blocked("Mason install failures", unreadable, { "remove it; failed installs are then tried again" })
  end

  -- The merged options run the gate's filter; what it held back is listed too.
  local asked = LazyVim.opts("mason.nvim").ensure_installed or {}

  for _, name in ipairs(gate and gate.requested or asked) do
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

function M.check()
  vim.health.start("Language servers")
  attach_rules()
  servers()
  vim.health.start("Mason packages")
  mason_packages()
end

return M
