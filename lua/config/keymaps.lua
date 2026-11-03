local ok, err = pcall(require("chkeys").setup, { per_key_window = vim.g.neovide ~= nil })
if not ok then
  vim.notify("chkeys: " .. tostring(err), vim.log.levels.ERROR)
end

vim.keymap.set("n", "<leader>uK", function()
  require("chkeys").toggle()
end, { desc = "Toggle ChKeys" })

require("indent_motion").setup()
