return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "elixir", "heex", "eex" } },
  },
  {
    -- expert is the language server; elixir-ls stays installed only for its debug adapter.
    "neovim/nvim-lspconfig",
    opts = { servers = { elixirls = { enabled = false } } },
  },
}
