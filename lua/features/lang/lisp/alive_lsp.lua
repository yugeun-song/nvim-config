-- alive-lsp, the Common Lisp language server: sbcl runs it from the directory ocicl installed it into
-- (docs/features/lang.md#common-lisp). lua/plugins/lang/lisp.lua enables it and :checkhealth reports it by ready().
local M = {}

function M.directory()
  return require("features.util.storage").path("data", "alive_lsp")
end

function M.ready()
  return vim.fn.executable("sbcl") == 1 and vim.uv.fs_stat(vim.fs.joinpath(M.directory(), "ocicl.csv")) ~= nil
end

return M
