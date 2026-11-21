-- Rust through rustaceanvim, which runs its own rust-analyzer and finds the cargo targets and Mason's codelldb.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "rust" } },
  },
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "rust-analyzer" } },
  },
  {
    "mrcjkb/rustaceanvim",
    ft = { "rust" },
    -- stylua: ignore
    keys = {
      { "<leader>dLr", function() vim.cmd.RustLsp("debuggables") end, desc = "Debug: rust debuggables", ft = "rust" },
    },
    config = function()
      local opts = {
        server = {
          -- rustaceanvim would connect rust-analyzer to 127.0.0.1:27631 whenever `pgrep lspmux` finds a process of
          -- that name, another user's too, who would then read the code and could edit files.
          lspmux = { enable = false },
          settings = function(project_root, default_settings)
            local settings = require("rustaceanvim.config.server").load_rust_analyzer_settings(project_root, {
              default_settings = default_settings,
            })

            local detached = not project_root
              or not vim.fs.find({ "Cargo.toml", "rust-project.json" }, { path = project_root, upward = true })[1]

            if detached then
              local ra = settings["rust-analyzer"]

              ra.cargo = vim.tbl_deep_extend("force", ra.cargo or {}, {
                extraEnv = { RUSTC_BOOTSTRAP = "1" },
                autoreload = false,
              })
            end

            return settings
          end,
        },
      }

      vim.g.rustaceanvim = vim.tbl_deep_extend("keep", vim.g.rustaceanvim or {}, opts)
    end,
  },
  {
    -- rustaceanvim runs its own rust-analyzer; lspconfig's would be a second one.
    "neovim/nvim-lspconfig",
    opts = { servers = { rust_analyzer = { enabled = false } } },
  },
  {
    -- rustaceanvim debugs through the adapter named codelldb when one is there: codelldb as a TCP server on
    -- 127.0.0.1, started and ended by lua/features/dap/managed_server.lua instead of nvim-dap.
    "mfussenegger/nvim-dap",
    optional = true,
    opts = function()
      require("dap").adapters.codelldb = require("features.dap.managed_server").adapter({
        name = "codelldb",
        cmd = function(port)
          local codelldb = vim.fn.exepath("codelldb")

          if codelldb == "" then
            return nil, "codelldb is not installed: :MasonInstall codelldb"
          end

          return { codelldb, "--port", tostring(port) }
        end,
      })
    end,
  },
}
