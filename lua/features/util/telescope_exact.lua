-- telescope opens an entry with :edit and fnameescape(), which leaves $ alone on Windows, where it is a path character:
-- x$TEMP.c opened x<temp>.c. The pickers of this configuration (code search, and cscope_maps' for <leader>i and gd in
-- assembler) open an entry by its exact name instead (lua/features/util/edit_file.lua), in the window, split or tab page
-- asked for, at its line and column.
local M = {}

-- attach_mappings for a picker whose entries carry path, lnum and a 0-based col.
function M.attach_mappings(prompt_bufnr)
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")

  local function open(where)
    return function()
      local entry = state.get_selected_entry()

      actions.close(prompt_bufnr)

      local path = entry and (entry.path or entry.filename)

      if not path then
        return
      end

      if where == "split" then
        vim.cmd.split()
      elseif where == "vsplit" then
        vim.cmd.vsplit()
      elseif where == "tab" then
        vim.cmd.tabnew()
      end

      require("features.util.edit_file").edit(path)
      pcall(vim.api.nvim_win_set_cursor, 0, { tonumber(entry.lnum) or 1, tonumber(entry.col) or 0 })
    end
  end

  actions.select_default:replace(open("edit"))
  actions.select_horizontal:replace(open("split"))
  actions.select_vertical:replace(open("vsplit"))
  actions.select_tab:replace(open("tab"))

  return true
end

local cscope_guarded = false

-- cscope_maps' telescope picker, whoever runs it: entries opened by their exact name.
function M.guard_cscope()
  local ok, picker = pcall(require, "cscope.pickers.telescope")

  if cscope_guarded or not ok then
    return
  end

  cscope_guarded = true

  local run = picker.run

  ---@diagnostic disable-next-line: duplicate-set-field
  picker.run = function(opts)
    opts = opts or {}
    opts.attach_mappings = opts.attach_mappings or M.attach_mappings

    return run(opts)
  end
end

return M
