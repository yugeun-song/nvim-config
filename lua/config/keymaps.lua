pcall(function()
  require("chkeys").setup({
    per_key_window = vim.g.neovide ~= nil,
  })
end)

vim.keymap.set("n", "<leader>uK", function()
  require("chkeys").toggle()
end, { desc = "Toggle ChKeys" })
