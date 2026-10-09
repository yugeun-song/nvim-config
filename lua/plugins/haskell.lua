local ghcup_bin = vim.fs.joinpath(vim.env.HOME, ".ghcup", "bin")
if vim.uv.fs_stat(ghcup_bin) and not vim.tbl_contains(vim.split(vim.env.PATH, ":", { plain = true }), ghcup_bin) then
  vim.env.PATH = ghcup_bin .. ":" .. vim.env.PATH
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "haskell" } },
  },
  {
    "mrcjkb/haskell-tools.nvim",
    version = "^11",
    ft = { "haskell", "lhaskell", "cabal", "cabalproject" },
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
            return not vim.bo.modified
          end,
        },
      },
    },
  },
}
