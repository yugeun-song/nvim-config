-- :checkhealth features.maintenance
local status = require("features.feature_status")

local M = {}

function M.check()
  vim.health.start("Maintenance")

  local paths = require("features.maintenance.stored_data_paths")

  status.available("Where everything is kept (:ManagedPaths, <leader>uM)", #paths.items() .. " places")

  if vim.uv.fs_stat(paths.script()) then
    status.available("Back to a fresh clone (:ManagedPathsReset, typed confirmation)", paths.script())
  else
    status.blocked("Back to a fresh clone (:ManagedPathsReset)", paths.script() .. " is missing")
  end
end

return M
