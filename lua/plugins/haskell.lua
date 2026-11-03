local win = vim.fn.has("win32") == 1
local sep = win and ";" or ":"
local ghcup_bin = win and "C:/ghcup/bin" or vim.fs.joinpath(vim.uv.os_homedir(), ".ghcup", "bin")
local on_path = vim.tbl_map(vim.fs.normalize, vim.split(vim.env.PATH or "", sep, { plain = true }))
if vim.uv.fs_stat(ghcup_bin) and not vim.list_contains(on_path, vim.fs.normalize(ghcup_bin)) then
  vim.env.PATH = (vim.env.PATH or "") .. sep .. ghcup_bin
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
