return {
  {
    "folke/snacks.nvim",
    opts = {
      bigfile = {
        enabled = true,
        size = 5 * 1024 * 1024,
      },
      picker = {
        sources = {
          explorer = {
            hidden = true,
            ignored = true,
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
