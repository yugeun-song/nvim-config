-- Where Neovim, the plugins and Neovide keep what they write (lua/features/maintenance/stored_data_paths.lua). Listing
-- has a key; the reset has none on purpose: only :ManagedPathsReset, which asks for "reset" to be typed.
return {
  "stored_data_paths",
  virtual = true,
  cmd = { "ManagedPaths", "ManagedPathsReset" },
  keys = {
    {
      "<leader>uM",
      function()
        require("features.maintenance.stored_data_paths").show()
      end,
      desc = "Managed paths (where Neovim keeps its data)",
    },
  },
  config = function()
    vim.api.nvim_create_user_command("ManagedPaths", function()
      require("features.maintenance.stored_data_paths").show()
    end, { desc = "Where Neovim, the plugins and Neovide keep what they write" })

    -- With "configuration": only this configuration's own files (lua/features/maintenance/local_storage.lua).
    vim.api.nvim_create_user_command("ManagedPathsReset", function(args)
      require("features.maintenance.stored_data_paths").reset(args.args)
    end, {
      nargs = "?",
      complete = function()
        return { "configuration" }
      end,
      desc = 'Quit and remove what :ManagedPaths marks "remove"; "configuration": only this configuration\'s files',
    })
  end,
}
