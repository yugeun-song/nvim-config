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
        messages = {
          goals = { accomplished = "Goals accomplished ✓" },
        },
      },
      abbreviations = { enable = true, leader = "\\" },
      progress_bars = { enable = true },
      stderr = { enable = true },
      -- Accomplished marker in the sign column; U+2713 is chosen for width.
      -- U+2714 is absent from CaskaydiaCove (fallback), U+2705 is full-width and
      -- misaligns a one-cell sign column; U+2713 is in both fonts and halfwidth.
      goal_markers = {
        unsolved = " ⚒ ",
        accomplished = "✓",
      },
    },
    config = function(_, opts)
      require("lean").setup(opts)

      -- lean.nvim links leanGoalsAccomplishedSign to DiagnosticInfo (blue) with
      -- default = true, which yields only when a definition already exists, so
      -- re-link it explicitly here to win. spaceduck's DiagnosticOk is #5ccc96.
      local function link_accomplished()
        vim.api.nvim_set_hl(0, "leanGoalsAccomplishedSign", { link = "DiagnosticOk" })
      end
      link_accomplished()
      vim.api.nvim_create_autocmd("ColorScheme", {
        desc = "lean.nvim: keep the accomplished sign green across colorscheme changes",
        callback = link_accomplished,
      })
    end,
  },
  -- No nvim-treesitter entry: it has no `lean` parser and warns at startup;
  -- lean.nvim registers its own.
}
