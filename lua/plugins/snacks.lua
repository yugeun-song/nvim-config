return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        sections = {
          function(self)
            return require("dashboard_header").section(self.opts.width)
          end,
          { section = "keys", gap = 1, padding = 1 },
          { section = "startup" },
        },
      },
      bigfile = {
        enabled = true,
        size = 5 * 1024 * 1024,
      },
      picker = {
        sources = {
          explorer = {
            hidden = true,
            ignored = true,
            watch = true,
          },
          files = {
            hidden = true,
            ignored = true,
          },
          grep = {
            hidden = true,
            ignored = true,
          },
        },
      },
    },
  },
}
