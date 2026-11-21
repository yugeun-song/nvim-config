local M = {}

-- Folder names as they are: a $NAME in one is no variable.
local function normalize(path)
  return vim.fs.normalize(path, { expand_env = false })
end

local function session_exists()
  local ok, persistence = pcall(require, "persistence")

  return ok
    and (
      vim.fn.filereadable(persistence.current()) == 1
      or vim.fn.filereadable(persistence.current({ branch = false })) == 1
    )
end

local function take(path)
  local ok, lines = pcall(vim.fn.readfile, path)

  os.remove(path)

  return ok and lines or {}
end

local history = require("features.util.storage").path("state", "open_folder_history")

local HISTORY_LIMIT = 100

-- Newest first.
function M.recent()
  local ok, dirs = pcall(vim.fn.readfile, history)

  return vim.tbl_filter(function(dir)
    return vim.fn.isdirectory(dir) == 1
  end, ok and dirs or {})
end

-- macOS and Windows file systems ignore case by default.
local fold = vim.fn.has("win32") == 1 or vim.fn.has("mac") == 1

local function key(dir)
  return fold and dir:lower() or dir
end

-- A folder's place in dirs, a list M.recent() returned (1: the folder opened last), or nil.
function M.place_in(dirs)
  local places = {}

  for place, dir in ipairs(dirs) do
    places[key(dir)] = place
  end

  return function(dir)
    return places[key(normalize(dir))]
  end
end

local function remember(dir)
  local dirs = { normalize(dir) }

  for _, old in ipairs(M.recent()) do
    if key(old) ~= key(dirs[1]) and #dirs < HISTORY_LIMIT then
      dirs[#dirs + 1] = old
    end
  end

  pcall(vim.fn.writefile, dirs, history)
end

function M.open(dir, files)
  files = files or {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and vim.bo[buf].modified then
      vim.notify("Save or discard the modified buffers first", vim.log.levels.WARN, { title = "Open Folder" })

      return
    end
  end

  -- Saves the folder being left the way persistence.nvim does on exit.
  pcall(vim.api.nvim_exec_autocmds, "VimLeavePre", { group = "persistence" })
  vim.cmd("silent! tabonly | silent! only | enew")
  local current = vim.api.nvim_get_current_buf()

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= current and vim.bo[buf].buflisted and vim.bo[buf].buftype == "" then
      vim.api.nvim_buf_delete(buf, {})
    end
  end

  vim.fn.chdir(dir)
  remember(dir)

  -- A folder without a session opens as LazyVim opens a directory (nvim DIR): the explorer beside the empty buffer.
  if session_exists() then
    require("persistence").load()
  elseif #files == 0 then
    Snacks.explorer.open({ cwd = vim.fn.getcwd() })
  end

  for _, file in ipairs(files) do
    require("features.util.edit_file").edit(file)
  end

  -- The language servers of the folder left, serving no buffer now, end: Neovim keeps a server until it quits, and
  -- clangd went on indexing the old tree on every core.
  vim.schedule(function()
    for _, client in ipairs(vim.lsp.get_clients()) do
      if next(client.attached_buffers) == nil and not client:is_stopped() then
        client:stop()
      end
    end
  end)
end

function M.pick()
  local cwd_file, chooser_file = vim.fn.tempname(), vim.fn.tempname()
  local cmd = { "yazi", "--cwd-file", cwd_file, "--chooser-file", chooser_file, vim.fn.getcwd() }
  local term = Snacks.terminal.open(cmd, {
    auto_close = false,
    win = {
      position = "float",
      width = 0.9,
      height = 0.9,
      border = "rounded",
      title = " Open Folder ",
      title_pos = "center",
      -- <Esc> is yazi's own key: twice in a row it would leave yazi for Normal mode, where its keys hit a terminal
      -- buffer (E21) and q closes the float under it.
      keys = { q = "close", term_normal = false },
    },
  })

  term:on("TermClose", function()
    local status = vim.v.event.status
    -- The float closed first (q in Normal mode) and stopped yazi: a cancel. Otherwise the float closes after this
    -- autocmd: deleting the buffer it runs for from inside it fails (E937).
    local cancelled = not term:win_valid()

    vim.schedule(function()
      if term:win_valid() then
        term:close()
      end

      local dir, chosen = take(cwd_file)[1], take(chooser_file)

      if cancelled then
        return
      end

      if status ~= 0 then
        vim.notify("yazi exited with code " .. status, vim.log.levels.ERROR, { title = "Open Folder" })
      end

      -- A folder selected (<Space>) and opened (<CR>) is the folder to open, not one inside its parent.
      local folder, files = nil, {}

      for _, path in ipairs(chosen) do
        if vim.fn.isdirectory(path) == 1 then
          folder = folder or path
        else
          files[#files + 1] = path
        end
      end

      if folder then
        dir = folder
      elseif files[1] then
        dir = vim.fs.root(files[1], ".git") or vim.fs.dirname(files[1])
      end

      if dir and (files[1] or normalize(dir) ~= normalize(vim.fn.getcwd())) then
        M.open(dir, files)
      end
    end)
  end, { buf = true })
end

-- `nvim DIR` / `neovide DIR`: start in DIR as Open Folder would, not on a directory buffer.
-- Runs before plugins load, while the argument is still buffer 1 and unread.
function M.startup()
  if vim.fn.argc(-1) ~= 1 then
    return
  end

  local dir = vim.fn.fnamemodify(vim.fn.argv(0) --[[@as string]], ":p")

  if vim.fn.isdirectory(dir) == 0 then
    return
  end

  vim.cmd("silent! %argdelete | silent keepalt 0file")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if normalize(vim.api.nvim_buf_get_name(buf)) == normalize(dir) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  vim.fn.chdir(dir)
  remember(dir)
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    nested = true,
    callback = function()
      if session_exists() then
        require("persistence").load()
      end
    end,
  })
end

return M
