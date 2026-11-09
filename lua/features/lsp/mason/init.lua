-- Mason's own directory, for specs that name a program before Mason has loaded and put its bin on PATH.
local M = {}

M.ROOT = vim.fs.joinpath(vim.fn.stdpath("data"), "mason")

-- Mason extends PATH only once loaded, and nvim-dap can come first. uv.spawn
-- finds Mason's Windows .cmd shims only by full name, which exepath gives.
function M.bin(name)
  local path = vim.fn.exepath(vim.fs.joinpath(M.ROOT, "bin", name))

  return path ~= "" and path or name
end

return M
