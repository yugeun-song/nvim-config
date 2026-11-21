-- mini.files: <CR> opens a file and closes the explorer, or enters a directory. Its bookmark keys pass the directory to
-- expand(), which on Linux and macOS runs a `command` in its name through the shell; m and ' set and go to bookmarks
-- here the same way without expand().
local function get_char()
  local ok, char = pcall(vim.fn.getcharstr)

  return ok and char ~= "\27" and char ~= "" and char or nil
end

local function mark_set()
  local id = get_char()

  if not id then
    return
  end

  local state = MiniFiles.get_explorer_state()
  local path = state and state.branch[state.depth_focus]

  if path then
    MiniFiles.set_bookmark(id, function()
      return path
    end, { desc = vim.fn.fnamemodify(path, ":~") })
  end
end

local function mark_goto()
  local id = get_char()
  local state = id and MiniFiles.get_explorer_state()

  if not state then
    return
  end

  local bookmark = state.bookmarks[id]

  if not bookmark then
    return vim.notify("No bookmark with id " .. vim.inspect(id), vim.log.levels.WARN)
  end

  local path = bookmark.path

  if vim.is_callable(path) then
    path = path()
  end

  if type(path) ~= "string" or vim.fn.isdirectory(path) ~= 1 then
    return vim.notify("Bookmark path should be a valid path to directory", vim.log.levels.WARN)
  end

  local here = state.branch[state.depth_focus]

  MiniFiles.set_bookmark("'", function()
    return here
  end, { desc = "Before latest jump" })

  MiniFiles.set_branch({ path })
end

return {
  "nvim-mini/mini.files",
  opts = function(_, opts)
    opts.mappings = opts.mappings or {}
    opts.mappings.mark_set = ""
    opts.mappings.mark_goto = ""

    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("MiniFilesEnterOpen", { clear = true }),
      pattern = "MiniFilesBufferCreate",
      callback = function(args)
        local buf = args.data.buf_id

        vim.keymap.set("n", "<CR>", function()
          require("mini.files").go_in({ close_on_file = true })
        end, { buffer = buf, desc = "Open entry (file/dir)" })

        vim.keymap.set("n", "m", mark_set, { buffer = buf, desc = "Set bookmark" })
        vim.keymap.set("n", "'", mark_goto, { buffer = buf, desc = "Go to bookmark" })
      end,
    })

    return opts
  end,
}
