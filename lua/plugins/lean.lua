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
    init = function()
      vim.g.lean_config = {
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
        abbreviations = { enable = true, leader = "\\", extra = {} },
        progress_bars = { enable = true },
        stderr = { enable = true },
        -- U+2713: halfwidth and in both fonts. U+2714 is missing from CaskaydiaCove,
        -- U+2705 is full-width and misaligns the sign column.
        goal_markers = {
          unsolved = " ⚒ ",
          accomplished = "✓",
        },
      }
    end,
    config = function()
      -- lean.nvim links this to DiagnosticInfo with default = true, which only
      -- yields to a link that already exists; set one explicitly.
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
