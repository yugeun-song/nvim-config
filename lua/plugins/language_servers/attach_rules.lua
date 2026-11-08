return {
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    require("features.language_servers.attach_rules").setup()

    return opts
  end,
  keys = {
    {
      "<leader>cFf",
      function()
        require("features.language_servers.attach_rules").add_current_file()
      end,
      desc = "LSP filter: exclude current file",
    },
    {
      "<leader>cFd",
      function()
        require("features.language_servers.attach_rules").add_current_dir()
      end,
      desc = "LSP filter: exclude ancestor dir",
    },
    {
      "<leader>cFa",
      function()
        require("features.language_servers.attach_rules").add_advanced()
      end,
      desc = "LSP filter: add (advanced)",
    },
    {
      "<leader>cFl",
      function()
        require("features.language_servers.attach_rules").list_current()
      end,
      desc = "LSP filter: rules for buffer",
    },
    {
      "<leader>cFe",
      function()
        require("features.language_servers.attach_rules").edit_registry()
      end,
      desc = "LSP filter: edit registry",
    },
    {
      "<leader>cFr",
      function()
        require("features.language_servers.attach_rules").reload()
      end,
      desc = "LSP filter: reload rules",
    },
    {
      "<leader>cFt",
      function()
        require("features.language_servers.attach_rules").toggle()
      end,
      desc = "LSP filter: toggle (session)",
    },
  },
}
