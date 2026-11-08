return {
  {
    "neovim/nvim-lspconfig",
    -- A function: ruff is looked for when nvim-lspconfig loads, not at every startup.
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers.ruff = vim.tbl_deep_extend("force", opts.servers.ruff or {}, {
        enabled = vim.fn.executable("ruff") == 1,
        mason = false,
        init_options = { settings = { logLevel = "error" } },
      })

      opts.setup = opts.setup or {}
      opts.setup.ruff = function()
        -- ty answers hover; ruff's would be a second popup.
        Snacks.util.lsp.on({ name = "ruff" }, function(_, client)
          client.server_capabilities.hoverProvider = false
        end)
      end
    end,
  },
  {
    "stevearc/conform.nvim",
    opts = { formatters_by_ft = { python = { "ruff_format" } } },
  },
}
