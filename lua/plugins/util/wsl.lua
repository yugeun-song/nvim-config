-- Windows only with at least one WSL distribution: :Wsl, <leader>fw, and dashboard shortcut `w`.
-- Zero startup cost, commands, or keymaps on Linux, macOS, or Windows without WSL.
if vim.fn.has("win32") == 0 then
  return {}
end

if not require("features.util.windows.wsl").is_available() then
  return {}
end

local function open_picker()
  require("features.util.windows.wsl").pick()
end

return {
  {
    "windows_wsl",
    virtual = true,
    cmd = "Wsl",
    keys = {
      { "<leader>fw", open_picker, desc = "Connect to WSL" },
    },
    config = function()
      vim.api.nvim_create_user_command("Wsl", function(args)
        require("features.util.windows.wsl").command(args.fargs)
      end, {
        nargs = "*",
        complete = function(lead, line)
          return require("features.util.windows.wsl").complete(lead, line)
        end,
        desc = "Connect host Windows Neovim or Neovide to WSL: Wsl [gui|tui] [DISTRO [DIR [FILES...]]]",
      })
    end,
  },
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      local items = opts.dashboard.preset.keys
      local pos = 1

      for i, item in ipairs(items) do
        if item.key == "o" then
          pos = i + 1
          break
        end
      end

      table.insert(items, pos, { icon = "\u{f17c} ", key = "w", desc = "Connect to WSL", action = open_picker })
    end,
  },
}
