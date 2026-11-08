return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ruff = {
          enabled = vim.fn.executable("ruff") == 1,
          mason = false,
          init_options = { settings = { logLevel = "error" } },
        },
      },
      setup = {
        ruff = function()
          -- ty answers hover; ruff's would be a second popup.
          Snacks.util.lsp.on({ name = "ruff" }, function(_, client)
            client.server_capabilities.hoverProvider = false
          end)
        end,
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = { formatters_by_ft = { python = { "ruff_format" } } },
  },
}
