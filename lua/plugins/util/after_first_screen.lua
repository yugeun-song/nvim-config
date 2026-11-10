-- Parts adapted from https://github.com/LazyVim/LazyVim (Apache-2.0). See THIRD-PARTY-NOTICES.
-- LazyVim loads these before a file's first screen, which needs neither: they load right after it (rule 3 of
-- docs/structure.md#lazy-loading). A C file's first screen: 91 to 63 ms.
return {
  {
    -- vim.lsp.enable() attaches the buffers already open, so the file's server still starts.
    "neovim/nvim-lspconfig",
    event = function()
      return { "VeryLazy" }
    end,
  },
  {
    -- Its signs wait for an asynchronous git diff anyway; setup attaches every open buffer.
    "lewis6991/gitsigns.nvim",
    event = function()
      return { "VeryLazy" }
    end,
  },
  {
    -- LazyVim's config, with the install check (a registry read and a lookup per package) a few seconds later.
    "mason-org/mason.nvim",
    config = function(_, opts)
      require("mason").setup(opts)

      local registry = require("mason-registry")

      registry:on("package:install:success", function()
        vim.defer_fn(function()
          require("lazy.core.handler.event").trigger({ event = "FileType", buf = vim.api.nvim_get_current_buf() })
        end, 100)
      end)

      vim.defer_fn(function()
        registry.refresh(function()
          for _, tool in ipairs(opts.ensure_installed or {}) do
            local package = registry.get_package(tool)

            if not package:is_installed() then
              package:install()
            end
          end
        end)
      end, 3000)
    end,
  },
}
