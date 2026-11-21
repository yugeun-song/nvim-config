-- The dashboard: this system's logo and NVIM, then the working directory, above LazyVim's keys
-- (lua/features/ui/dashboard.lua).
return {
  "folke/snacks.nvim",
  opts = {
    dashboard = {
      sections = {
        function(self)
          return require("features.ui.dashboard").section(self.opts.width)
        end,
        function(self)
          return require("features.ui.dashboard").folder(self.opts.width)
        end,
        { section = "keys", gap = 1, padding = 1 },
        { section = "startup" },
      },
    },
  },
}
