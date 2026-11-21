-- No language server for a buffer without a file (lua/features/lsp/file_buffers.lua): in place before nvim-lspconfig
-- enables any server.
return {
  "neovim/nvim-lspconfig",
  opts = function()
    require("features.lsp.file_buffers").install()
  end,
}
