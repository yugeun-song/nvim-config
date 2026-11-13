-- Markdown: markview renders it in place, rumdl lints it.
return {
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "rumdl" } },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        rumdl = {
          -- No line-length limit unless a project's rumdl or markdownlint config sets one.
          init_options = { configurationPreference = "filesystemFirst" },
          settings = { rumdl = { lineLength = 0 } },
        },
      },
    },
  },
  {
    "OXY2DEV/markview.nvim",
    -- Not on a trigger: markview defers its own work, and its README warns that lazy-loading it makes the first
    -- preview slower.
    lazy = false,
  },
}
