local ASM_DEFINERS = { "#%s*define", "%.macro", "%.set", "%.equ", "%.equiv", "%.eqv" }

local function defines(line, symbol)
  local name = vim.pesc(symbol)

  if line:find("^%s*" .. name .. "%s*[:=]") then
    return true
  end

  for _, definer in ipairs(ASM_DEFINERS) do
    if line:find("^%s*" .. definer .. "%s+" .. name .. "%f[^%w_]") then
      return true
    end
  end

  return false
end

-- cscope lexes assembler as C, where a mnemonic can read as a declaration.
local function real_definitions(hits, symbol)
  local kept = vim.tbl_filter(function(hit)
    return not hit.filename:find("%.[sS]x?$") or defines(hit.text:gsub("^<<.->>%s*", ""), symbol)
  end, hits)

  return #kept > 0 and kept or hits
end

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
    config = function(_, opts)
      require("cscope_maps").setup(opts)

      local cscope = require("cscope")
      local get_result = cscope.get_result

      ---@diagnostic disable-next-line: duplicate-set-field
      cscope.get_result = function(op_n, op_s, symbol, hide_log)
        local rc, hits = get_result(op_n, op_s, symbol, hide_log)

        return rc, op_s == "g" and hits and real_definitions(hits, symbol) or hits
      end
    end,
  },
}
