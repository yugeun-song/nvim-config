return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    -- LazyVim installs its own list too (c, bash, lua, markdown, python, ...); lazy.nvim joins the two. The
    -- assembly parsers come with lua/plugins/languages/assembly.lua.
    ensure_installed = {
      "awk",
      "c",
      "cpp",
      "css",
      "cuda",
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
      "racket",
      "rust",
    },
  },
}
