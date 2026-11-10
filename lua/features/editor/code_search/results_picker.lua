-- The hits in the Telescope picker of the <leader>i keys (cscope_maps.nvim's); a column, when given, places the cursor.
local M = {}

-- cscope_maps' get_rel_path: ../ for every directory of base the path is not under.
local function relative(base, path)
  local inside = vim.fs.relpath(base, path)

  if inside then
    return inside
  end

  local from, to = vim.split(vim.fs.normalize(base), "/"), vim.split(vim.fs.normalize(path), "/")
  local i = 1

  while i <= #from and i <= #to and from[i] == to[i] do
    i = i + 1
  end

  return ("../"):rep(#from - i + 1) .. table.concat(to, "/", i)
end

local function entry_maker(item)
  local shown = relative(vim.fn.getcwd(), item.filename)

  return {
    value = item,
    display = function()
      local coordinates = item.file_only and ""
        or item.col and (":%d:%d:"):format(item.lnum, item.col + 1)
        or (":%d:"):format(item.lnum)
      local display, hl_group, icon =
        require("telescope.utils").transform_devicons(item.filename, shown .. coordinates .. item.text, false)

      if hl_group then
        return display, { { { 1, #icon }, hl_group } }
      end

      return display
    end,
    ordinal = shown .. item.text,
    path = item.filename,
    lnum = item.lnum,
    col = item.col,
  }
end

-- As cscope_maps' open_picker: the search goes on the tag stack and the jump list, so <C-t> and <C-o> come back.
local function remember_origin(tagname)
  local from = { vim.fn.bufnr("%"), vim.fn.line("."), vim.fn.col("."), 0 }

  vim.fn.settagstack(vim.fn.win_getid(), { items = { { tagname = tagname, from = from } } }, "t")
  vim.cmd.normal({ "m'", bang = true })
end

-- items: { filename (absolute), lnum, col (0-based byte, optional), text, file_only }.
function M.open(title, items, tagname)
  local ok, pickers = pcall(require, "telescope.pickers")

  if not ok then
    return require("features.editor.code_search.search_job").notify(
      "telescope.nvim does not load: " .. tostring(pickers),
      vim.log.levels.ERROR
    )
  end

  local finders = require("telescope.finders")
  local config = require("telescope.config")
  local opts = {}

  remember_origin(tagname)
  pickers
    .new(opts, {
      prompt_title = title,
      finder = finders.new_table({ results = items, entry_maker = entry_maker }),
      previewer = config.values.grep_previewer(opts),
      sorter = config.values.generic_sorter(opts),
    })
    :find()
end

return M
