-- ghcup's bin joins PATH with the first Haskell buffer (lua/features/lang/haskell.lua), not at startup.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "haskell" } },
  },
  {
    "mrcjkb/haskell-tools.nvim",
    version = "^11",
    ft = { "haskell", "lhaskell", "cabal", "cabalproject" },
    -- haskell-tools is set up through vim.g; loading it is when its programs have to be found.
    config = function()
      require("features.lang.haskell").add_to_path()
    end,
    keys = {
      { "<localleader>e", "<cmd>Haskell hls evalAll<cr>", desc = "Evaluate All", ft = "haskell" },
      {
        "<localleader>h",
        function()
          require("haskell-tools").hoogle.hoogle_signature()
        end,
        desc = "Hoogle Signature",
        ft = "haskell",
      },
      {
        "<localleader>r",
        function()
          ---@diagnostic disable-next-line: missing-parameter
          require("haskell-tools").repl.toggle()
        end,
        desc = "REPL (Package)",
        ft = "haskell",
      },
      {
        "<localleader>R",
        function()
          require("haskell-tools").repl.toggle(vim.api.nvim_buf_get_name(0))
        end,
        desc = "REPL (Buffer)",
        ft = "haskell",
      },
    },
  },
  {
    -- haskell-tools runs its own haskell-language-server; lspconfig's would be a second one.
    "neovim/nvim-lspconfig",
    opts = { servers = { hls = { enabled = false } } },
  },
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = { haskell = { "hlint" } },
      linters = {
        hlint = {
          condition = function()
            require("features.lang.haskell").add_to_path()

            return not vim.bo.modified
          end,
        },
      },
    },
  },
}
