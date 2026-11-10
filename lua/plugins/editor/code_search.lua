-- Code search by a typed pattern (lua/features/editor/code_search/): <leader>i/ or :CodeSearch, loaded on first use.
return {
  {
    "code_search",
    virtual = true,
    cmd = "CodeSearch",
    keys = {
      {
        "<leader>i/",
        function()
          require("features.editor.code_search").choose()
        end,
        desc = "Code Search: Choose Tool, Type Pattern",
      },
    },
    config = function()
      require("features.editor.code_search").create_command()
    end,
  },
  {
    "folke/which-key.nvim",
    opts = { spec = { { "<leader>i", group = "code index" } } },
  },
}
