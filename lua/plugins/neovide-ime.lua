return {
  "sevenc-nanashi/neov-ime.nvim",
  cond = function()
    return vim.g.neovide ~= nil
  end,
  lazy = false,
}
