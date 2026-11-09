-- :checkhealth features.lsp: language servers and Mason packages. The servers are the ones the merged configuration enables, each checked
-- by the command Neovim would start it with.
local status = require("features.util.feature_status")

local M = {}

local function attach_rules()
  local rules = require("features.lsp.attach_rules")
  local path = rules.registry_path()

  if not vim.uv.fs_stat(path) then
    status.available("Attach rules (<leader>cF)", "none written: every server attaches wherever it is configured")

    return
  end

  local ok, text = pcall(vim.fn.readfile, path)
  local decoded, err = false, nil

  if ok then
    decoded, err = pcall(vim.json.decode, table.concat(text, "\n"))
  end

  if ok and decoded then
    status.available("Attach rules (<leader>cF)", path)
  else
    status.blocked("Attach rules (<leader>cF)", ("%s cannot be read: %s"):format(path, tostring(err or text)), {
      "<leader>cFe edits it",
    })
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

  local runtimes = require("features.lsp.mason.runtime_requirements")
  local gate = status.WINDOWS and require("features.lsp.mason.windows_install_gate") or nil
  local failures = gate and gate.failures() or {}
  local installed = {}

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
