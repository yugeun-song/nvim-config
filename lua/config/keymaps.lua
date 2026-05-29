-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

pcall(function()
  require("chkeys").setup({
    per_key_window = vim.g.neovide ~= nil,
  })
end)

vim.keymap.set("n", "<leader>uK", function()
  require("chkeys").toggle()
end, { desc = "Toggle ChKeys" })
