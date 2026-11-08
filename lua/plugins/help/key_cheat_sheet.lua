-- Every key in one searchable list (lua/features/help/key_cheat_sheet.lua): <leader>sK or :KeyCheatSheet. Nothing
-- loads before one of them is used.
return {
  "key_cheat_sheet",
  virtual = true,
  cmd = "KeyCheatSheet",
  keys = {
    {
      "<leader>sK",
      function()
        require("features.help.key_cheat_sheet").open()
      end,
      desc = "All keys: mappings and built-ins",
    },
  },
  config = function()
    vim.api.nvim_create_user_command("KeyCheatSheet", function()
      require("features.help.key_cheat_sheet").open()
    end, { desc = "Every key: this configuration's, the plugins', Neovim's mappings and built-in commands" })
  end,
}
