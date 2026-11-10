return {
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    require("features.lsp.attach_rules").setup()

    return opts
  end,
  keys = {
    {
      "<leader>cLf",
      function()
        require("features.lsp.attach_rules").add_current_file()
      end,
      desc = "LSP filter: exclude current file",
    },
    {
      "<leader>cLd",
      function()
        require("features.lsp.attach_rules").add_current_dir()
      end,
      desc = "LSP filter: exclude ancestor dir",
    },
    {
      "<leader>cLa",
      function()
        require("features.lsp.attach_rules").add_advanced()
      end,
      desc = "LSP filter: add (advanced)",
    },
    {
      "<leader>cLl",
      function()
        require("features.lsp.attach_rules").list_current()
      end,
      desc = "LSP filter: rules for buffer",
    },
    {
      "<leader>cLe",
      function()
        require("features.lsp.attach_rules").edit_registry()
      end,
      desc = "LSP filter: edit registry",
    },
    {
      "<leader>cLr",
      function()
        require("features.lsp.attach_rules").reload()
      end,
      desc = "LSP filter: reload rules",
    },
    {
      "<leader>cLt",
      function()
        require("features.lsp.attach_rules").toggle()
      end,
      desc = "LSP filter: toggle (session)",
    },
  },
}
