-- Files opened by their exact name. :edit reads its argument as a file pattern, and vim.fn.fnameescape() leaves $
-- alone on Windows, where it is a path character, so x$HOME.txt would open x<home>.txt; :drop expands $ and splits at
-- spaces even with magic.file off. Here nothing in the name is expanded: no $VAR, %, #, `backtick`, wildcard or space.
local M = {}

local function run(cmd, path, mods)
  -- A leading + would still be read as +command or ++opt.
  if path:sub(1, 1) == "+" then
    path = "./" .. path
  end

  vim.api.nvim_cmd({ cmd = cmd, args = { path }, magic = { file = false, bar = false }, mods = mods }, {})
end

function M.edit(path, mods)
  run("edit", path, mods)
end

function M.vsplit(path, mods)
  run("vsplit", path, mods)
end

-- :drop: a window that shows the file, this tab page's first, then another tab page's; else :edit in the current one.
function M.drop(path)
  local buf = require("features.util.buffer_by_name").find(vim.fn.fnamemodify(path, ":p"))
  local current = vim.api.nvim_get_current_tabpage()

  if buf then
    local tabs = { current }

    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      if tab ~= current then
        tabs[#tabs + 1] = tab
      end
    end

    for _, tab in ipairs(tabs) do
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if vim.api.nvim_win_get_buf(win) == buf then
          vim.api.nvim_set_current_tabpage(tab)
          vim.api.nvim_set_current_win(win)

          return
        end
      end
    end
  end

  M.edit(path)
end

return M
