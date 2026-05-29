return {
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    pcall(function()
      require("lsp_filter").setup({
        default_servers = { "clangd" },
        default_action = "disable",
      })
    end)
    return opts
  end,
  keys = {
    { "<leader>cFf", function() require("lsp_filter").add_current_file() end, desc = "LSP filter: exclude current file" },
    { "<leader>cFd", function() require("lsp_filter").add_current_dir() end, desc = "LSP filter: exclude ancestor dir" },
    { "<leader>cFa", function() require("lsp_filter").add_advanced() end, desc = "LSP filter: add (advanced)" },
    { "<leader>cFl", function() require("lsp_filter").list_current() end, desc = "LSP filter: rules for buffer" },
    { "<leader>cFe", function() require("lsp_filter").edit_registry() end, desc = "LSP filter: edit registry" },
    { "<leader>cFr", function() require("lsp_filter").reload() end, desc = "LSP filter: reload rules" },
    { "<leader>cFt", function() require("lsp_filter").toggle() end, desc = "LSP filter: toggle (session)" },
  },
}
