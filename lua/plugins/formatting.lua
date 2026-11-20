-- Formatters that serve several languages; a language's own comes with its file in lua/plugins/lang/.
return {
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "oxfmt", "taplo" } },
  },
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
      formatters = {
        -- Mason's or PATH's oxfmt; conform's own definition prefers <root>/node_modules/.bin/oxfmt, a repository's
        -- program, which would run on save.
        oxfmt = { command = "oxfmt" },
      },
    },
  },
}
