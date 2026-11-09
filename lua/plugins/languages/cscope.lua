return {
  {
    "dhananjaylatkar/cscope_maps.nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
    -- Windows opens a file without loading this and Telescope (about 22 ms there): its commands and keys load it,
    -- and so does a tree with a cscope.out, through :Cs in lua/config/autocmds.lua.
    event = vim.fn.has("win32") == 0 and { "BufReadPre", "BufNewFile" } or nil,
    cmd = vim.fn.has("win32") == 1 and { "Cs", "Cscope", "Cstag" } or nil,
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
    config = function(_, opts)
      require("cscope_maps").setup(opts)

      local cscope = require("cscope")
      local get_result = cscope.get_result

      ---@diagnostic disable-next-line: duplicate-set-field
      cscope.get_result = function(op_n, op_s, symbol, hide_log)
        local file = vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) or ""
        local from = file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
        local database = vim.fs.find("cscope.out", { upward = true, path = from })[1]

        vim.g.cscope_maps_db_file = database and database .. "::@" or nil

        local rc, hits = get_result(op_n, op_s, symbol, hide_log)

        if op_s ~= "g" or not hits then
          return rc, hits
        end

        local kept = require("features.languages.assembly.definition_navigation").real_definitions(hits, symbol)

        return rc, #kept > 0 and kept or hits
      end
    end,
  },
}
