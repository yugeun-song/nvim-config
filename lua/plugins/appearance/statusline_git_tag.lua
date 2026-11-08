-- The latest git tag in the statusline (lua/features/appearance/statusline_git_tag.lua).
return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      require("features.appearance.statusline_git_tag").add_to_statusline(opts)
    end,
  },
}
