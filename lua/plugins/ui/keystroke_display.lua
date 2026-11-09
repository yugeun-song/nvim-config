-- ChKeys, the keystroke display (lua/features/ui/keystroke_display.lua): off until <leader>uK or :ChKeysToggle,
-- which load it and set it up on first use.
local function toggle()
  local display = require("features.ui.keystroke_display")
  local ok, err = pcall(display.setup, { per_key_window = vim.g.neovide ~= nil })

  if ok then
    display.toggle()
  else
    vim.notify("chkeys: " .. tostring(err), vim.log.levels.ERROR)
  end
end

return {
  "keystroke_display",
  virtual = true,
  cmd = "ChKeysToggle",
  keys = {
    { "<leader>uK", toggle, desc = "Toggle ChKeys" },
  },
  config = function()
    vim.api.nvim_create_user_command("ChKeysToggle", toggle, { desc = "Toggle ChKeys" })
  end,
}
