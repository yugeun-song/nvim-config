-- Snacks' pickers: the explorer, files and grep include hidden and ignored files (files and grep skip .cache), the
-- explorer watches the disk, and <leader>ba lists every buffer.
return {
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
          exclude = { ".cache" },
        },
        grep = {
          hidden = true,
          ignored = true,
          exclude = { ".cache" },
        },
      },
    },
  },
}
