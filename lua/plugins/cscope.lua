return {
  {
    "dhananjaylatkar/cscope_maps.nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
    opts = {
      disable_navigation_mappings = false,
      use_telescope = true,
      cscope = {
        picker = "telescope",
      },
    },
    keys = {
      { "<leader>cs", [[<cmd>exe "Cscope find s " . expand("<cword>")<cr>]], desc = "Cscope Find Symbol" },
      { "<leader>cg", [[<cmd>exe "Cscope find g " . expand("<cword>")<cr>]], desc = "Cscope Find Definition" },
      { "<leader>cc", [[<cmd>exe "Cscope find c " . expand("<cword>")<cr>]], desc = "Cscope Find Callees" },
    },
  },
}
