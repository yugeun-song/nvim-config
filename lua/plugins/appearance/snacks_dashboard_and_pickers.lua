return {
  {
    "folke/snacks.nvim",
    keys = {
      -- Every buffer in one list: which-key numbers only ten under <leader>b. The pick opens in the window it was
      -- asked from, or the nearest editing window when that one is the explorer or another special window.
      {
        "<leader>ba",
        function()
          Snacks.picker.buffers({ current = true, sort_lastused = true })
        end,
        desc = "All Buffers (picker)",
      },
    },
    opts = {
      dashboard = {
        sections = {
          function(self)
            return require("features.appearance.dashboard_header").section(self.opts.width)
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
