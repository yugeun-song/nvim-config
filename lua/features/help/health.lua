-- :checkhealth features.help
local status = require("features.feature_status")

local M = {}

function M.check()
  vim.health.start("Help")

  local index = vim.fs.joinpath(vim.env.VIMRUNTIME, "doc", "index.txt")

  if vim.uv.fs_stat(index) then
    status.available("Key cheat sheet (<leader>sK, :KeyCheatSheet)", "mappings and " .. index)
  else
    status.blocked("Key cheat sheet (<leader>sK)", index .. " is missing: only mappings are listed")
  end
end

return M
