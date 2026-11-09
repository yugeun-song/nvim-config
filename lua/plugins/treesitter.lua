return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    -- Parsers of the languages without a file in lua/plugins/lang/, which add their own. LazyVim installs its
    -- own list too (c, bash, lua, markdown, python, ...); the lists are joined.
    ensure_installed = {
      "awk",
      "css",
      "dockerfile",
      "erlang",
      "git_config",
      "git_rebase",
      "gitattributes",
      "gitcommit",
      "java",
      "julia",
      "kconfig",
      "kotlin",
      "make",
    },
  },
}
