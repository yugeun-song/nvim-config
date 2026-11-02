return {
  "ifdef_all",
  virtual = true,
  event = "VeryLazy",
  config = function()
    local ifdef_all = require("ifdef_all")
    ifdef_all.setup()
    Snacks.toggle({
      name = "All #if Branches",
      get = function()
        return ifdef_all.enabled
      end,
      set = ifdef_all.set,
    }):map("<leader>uB")
  end,
}
