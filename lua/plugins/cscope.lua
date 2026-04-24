return {
  {
    "dhananjaylatkar/cscope_maps.nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
    event = { "BufReadPre", "BufNewFile" },
    keys = {
      { "<leader>is", [[<cmd>exe "Cscope find s " . expand("<cword>")<cr>]], desc = "Cscope: Find Symbol" },
      { "<leader>ig", [[<cmd>exe "Cscope find g " . expand("<cword>")<cr>]], desc = "Cscope: Find Global Def" },
      { "<leader>ic", [[<cmd>exe "Cscope find c " . expand("<cword>")<cr>]], desc = "Cscope: Find Callers" },
      { "<leader>id", [[<cmd>exe "Cscope find d " . expand("<cword>")<cr>]], desc = "Cscope: Find Callees" },
      { "<leader>it", [[<cmd>exe "Cscope find t " . expand("<cword>")<cr>]], desc = "Cscope: Find Text" },
      { "<leader>ie", [[<cmd>exe "Cscope find e " . expand("<cword>")<cr>]], desc = "Cscope: Find Egrep" },
      { "<leader>if", [[<cmd>exe "Cscope find f " . expand("<cfile>")<cr>]], desc = "Cscope: Find File" },
      { "<leader>ii", [[<cmd>exe "Cscope find i " . expand("<cfile>")<cr>]], desc = "Cscope: Find Includes" },
      { "<leader>ia", [[<cmd>exe "Cscope find a " . expand("<cword>")<cr>]], desc = "Cscope: Find Assignments" },
    },
    opts = {
      disable_maps = true,
      cscope = {
        db_file = {},
        picker = "telescope",
        tag = {
          keymap = false,
        },
      },
    },
  },
}
