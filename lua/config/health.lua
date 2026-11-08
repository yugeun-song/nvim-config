-- :checkhealth config: what every feature stands on. Each feature checks itself next to its code
-- (lua/features/*/health.lua, :checkhealth features.*); :FeatureStatus runs both.
local status = require("features.feature_status")

local M = {}

function M.check()
  vim.health.start("Core")

  if vim.fn.has("nvim-0.12") == 1 then
    status.available("Neovim " .. tostring(vim.version()))
  else
    vim.health.error("Neovim " .. tostring(vim.version()) .. " is older than 0.12")
  end

  local plugins = require("lazy.core.config").plugins
  local missing = {}

  for name, plugin in pairs(plugins) do
    if not plugin.virtual and not status.plugin_installed(name) then
      missing[#missing + 1] = name
    end
  end

  table.sort(missing)
  if #missing == 0 then
    status.available("Plugins", "every plugin of the spec is installed")
  else
    status.blocked("Plugins", "not installed: " .. table.concat(missing, ", "), { ":Lazy install" })
  end

  status.programs("Plugins and their updates", { "git" })
  status.programs("Pickers and grep", { "rg", { "fd", "fdfind" } })
end

return M
