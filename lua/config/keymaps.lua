-- The keystroke display is off until toggled, so it loads and sets itself up on the first toggle.
local function toggle_keystroke_display()
  local display = require("features.appearance.keystroke_display")
  local ok, err = pcall(display.setup, { per_key_window = vim.g.neovide ~= nil })

  if ok then
    display.toggle()
  else
    vim.notify("chkeys: " .. tostring(err), vim.log.levels.ERROR)
  end
end

vim.keymap.set("n", "<leader>uK", toggle_keystroke_display, { desc = "Toggle ChKeys" })
vim.api.nvim_create_user_command("ChKeysToggle", toggle_keystroke_display, { desc = "Toggle ChKeys" })

require("features.editing.indent_stop_motion").setup()
