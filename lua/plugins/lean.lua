-- Lean 4. The server comes from elan, not Mason: `lake serve` runs the toolchain
-- the project pins, and a Mason binary would be a different version.
return {
  {
    "Julian/lean.nvim",
    ft = "lean",
    dependencies = {
      "neovim/nvim-lspconfig",
      "nvim-lua/plenary.nvim",
    },
    opts = {
      mappings = true,
      -- lean.nvim starts the server itself, so `lean` must stay out of
      -- nvim-lspconfig's opts.servers or two would start.
      lsp = {
        init_options = { editDelay = 200, hasWidgets = true },
      },
      infoview = {
        autoopen = true,
        width = 60,
        height = 20,
        horizontal_position = "bottom",
        indicators = "auto",
      },
      abbreviations = { enable = true, leader = "\\" },
      progress_bars = { enable = true },
      stderr = { enable = true },
    },
  },
  -- No nvim-treesitter entry: it has no `lean` parser and warns at startup;
  -- lean.nvim registers its own.
}
