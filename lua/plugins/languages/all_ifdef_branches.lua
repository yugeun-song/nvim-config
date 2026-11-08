return {
  "ifdef_all",
  virtual = true,
  -- With the first C-family buffer: its state-file watcher has nothing to do before one.
  ft = require("features.languages.c_and_cpp.all_ifdef_branches.filetypes"),
  config = function()
    local ifdef_all = require("features.languages.c_and_cpp.all_ifdef_branches")

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
