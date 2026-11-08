-- :checkhealth features.language_servers. The servers are the ones the merged configuration enables, each checked
-- by the command Neovim would start it with.
local status = require("features.feature_status")

local M = {}

local function attach_rules()
  local rules = require("features.language_servers.attach_rules")
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

function M.check()
  vim.health.start("Language servers")
  attach_rules()
  servers()
end

return M
