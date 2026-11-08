-- :checkhealth features.integrations
local status = require("features.feature_status")

local M = {}

function M.check()
  vim.health.start("Integrations")

  local supported, running, state = require("features.integrations.discord_rich_presence").status()

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

return M
