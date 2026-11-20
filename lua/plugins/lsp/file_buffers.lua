-- No language server for a buffer without a file (lua/features/lsp/file_buffers.lua). lua/config/lazy.lua imports this
-- directory after the languages, so every server they add is gated.
return {
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    opts.servers = opts.servers or {}
    require("features.lsp.file_buffers").apply(opts.servers)
  end,
}
