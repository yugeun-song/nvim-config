-- Parts adapted from https://github.com/LazyVim/LazyVim (Apache-2.0). See THIRD-PARTY-NOTICES.
-- Python: ty answers as the language server, ruff lints and formats, debugpy debugs.
return {
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "debugpy", "ty" } },
  },
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
  {
    "mfussenegger/nvim-dap",
    optional = true,
    dependencies = {
      {
        "mfussenegger/nvim-dap-python",
        -- stylua: ignore
        keys = {
          { "<leader>dPt", function() require("dap-python").test_method() end, desc = "Debug: python test method", ft = "python" },
          { "<leader>dPc", function() require("dap-python").test_class() end, desc = "Debug: python test class", ft = "python" },
        },
        config = function()
          local venv = vim.fs.joinpath(require("features.lsp.mason").ROOT, "packages", "debugpy", "venv")
          local python =
            vim.fn.exepath(vim.fs.joinpath(venv, vim.fn.has("win32") == 1 and "Scripts" or "bin", "python"))

          require("dap-python").setup(python ~= "" and python or nil)
        end,
      },
    },
  },
}
