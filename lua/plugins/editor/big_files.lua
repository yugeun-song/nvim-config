-- From 5 MiB a file opens without the features that slow on it (Snacks' bigfile).
return {
  "folke/snacks.nvim",
  opts = {
    bigfile = {
      enabled = true,
      size = 5 * 1024 * 1024,
    },
  },
}
