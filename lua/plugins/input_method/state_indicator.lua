-- The IME and Caps Lock indicators (lua/features/input_method/state_indicator.lua). Nothing here runs while the
-- specs are read: the module, and the IME tools it asks for, load with the statusline.
return {
  {
    "imstate",
    virtual = true,
    event = "VeryLazy",
    config = function()
      require("features.input_method.state_indicator").start()
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      for i, component in ipairs(require("features.input_method.state_indicator").statusline_components()) do
        table.insert(opts.sections.lualine_x, i, component)
      end
    end,
  },
}
