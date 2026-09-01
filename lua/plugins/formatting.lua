return {
  {
    "neovim/nvim-lspconfig",
    opts = { servers = { oxfmt = { enabled = false } } },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        javascript = { "oxfmt" },
        javascriptreact = { "oxfmt" },
        typescript = { "oxfmt" },
        typescriptreact = { "oxfmt" },
        json = { "oxfmt" },
        jsonc = { "oxfmt" },
        json5 = { "oxfmt" },
        css = { "oxfmt" },
        scss = { "oxfmt" },
        less = { "oxfmt" },
        html = { "oxfmt" },
        toml = { "taplo" },
      },
    },
  },
}
