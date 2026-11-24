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

-- Over the dashboard, a folder without a session gets what LazyVim gives it: the file picker for a project picked
-- (Projects), else the explorer at the folder, as for nvim DIR.
local function show_new_folder(pick_files)
  if pick_files then
    Snacks.picker.files()
  else
    Snacks.explorer.open({ cwd = vim.fn.getcwd() })
  end
end

-- opts.pick_files: picked in Projects, so a folder without a session shows the file picker, not the explorer.
function M.open(dir, files, opts)
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

  if session_exists() then
    require("persistence").load()
  elseif #files == 0 then
    ---@diagnostic disable-next-line: missing-fields
    Snacks.dashboard({ buf = current, win = vim.api.nvim_get_current_win() })
    show_new_folder(opts and opts.pick_files)
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

-- The terminal output kept for a file manager that prints its result: far more than what follows its alternate screen.
local STDOUT_TAIL = 65536

-- What the file manager left, as the folder to open and the files to edit; reports what it cannot use.
local function choice(file_managers, name, dir, chosen)
  if dir ~= nil and (type(dir) ~= "string" or vim.fn.isabsolutepath(dir) == 0 or vim.fn.isdirectory(dir) == 0) then
    file_managers.report(("%s reported %q, which is not a folder"):format(name, tostring(dir)))
    dir = nil
  end

  -- A folder selected (<Space> in yazi) and opened (<CR>) is the folder to open, not one inside its parent.
  local folder, files = nil, {}

  for _, path in ipairs(chosen) do
    if type(path) ~= "string" or vim.fn.isabsolutepath(path) == 0 then
      file_managers.report(
        ("%s chose %q, which is not an absolute path; it is not opened"):format(name, tostring(path))
      )
    elseif vim.fn.isdirectory(path) == 1 then
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

  return dir, files
end

-- Runs the first installed file manager of lua/features/editor/file_managers.lua in a float at the working directory.
function M.pick()
  local file_managers = require("features.editor.file_managers")
  local fm = file_managers.find()

  if not fm then
    pcall(vim.keymap.del, "n", "<leader>fo")
    file_managers.report("Open Folder disabled: no working file manager is available", vim.log.levels.WARN)

    return
  end

  local out = { cwd_file = vim.fn.tempname(), chooser_file = vim.fn.tempname() }
  local made, argv, env = pcall(fm.command, vim.fn.getcwd(), out)

  if not made or type(argv) ~= "table" or type(argv[1]) ~= "string" or (env ~= nil and type(env) ~= "table") then
    file_managers.report(("%s: command() gave no command (%s)"):format(fm.name, made and vim.inspect(argv) or argv))

    return
  end

  local captured = ""
  local term = Snacks.win({
    style = "terminal",
    bo = { filetype = "snacks_terminal" },
    position = "float",
    width = 0.9,
    height = 0.9,
    border = "rounded",
    title = " Open Folder ",
    title_pos = "center",
    -- <Esc> is the file manager's own key: twice in a row it would leave it for Normal mode, where its keys hit a
    -- terminal buffer (E21) and q closes the float under it.
    keys = { q = "close", term_normal = false },
    on_win = function(self)
      if vim.api.nvim_get_current_buf() == self.buf then
        vim.cmd.startinsert()
      end
    end,
  })

  term:on("BufEnter", function()
    vim.cmd.startinsert()
  end, { buf = true })

  term:on("ExitPre", function()
    term:close()
  end)

  local function finish(status)
    -- The float closed first (q in Normal mode) and stopped the file manager: a cancel.
    local cancelled = not term:win_valid()

    vim.schedule(function()
      if term:win_valid() then
        term:close()
      end

      local got = {
        cwd_file = take(out.cwd_file),
        chooser_file = take(out.chooser_file),
        stdout = fm.capture_stdout and file_managers.after_alternate_screen(captured) or nil,
      }

      if cancelled then
        return
      end

      if status ~= 0 then
        file_managers.report(("%s exited with code %d"):format(fm.name, status))
      end

      local read, dir, chosen, err = pcall(fm.read, got)

      if not read then
        file_managers.report(("%s: reading what it left failed: %s"):format(fm.name, dir))

        return
      end

      if err then
        if status == 0 then
          file_managers.report(("%s %s; the folder is not opened"):format(fm.name, err))
        end

        dir = nil
      end

      local files

      dir, files = choice(file_managers, fm.name, dir, type(chosen) == "table" and chosen or {})

      if dir and (files[1] or normalize(dir) ~= normalize(vim.fn.getcwd())) then
        M.open(dir, files)
      end
    end)
  end

  local started, job = pcall(vim.api.nvim_buf_call, term.buf, function()
    return vim.fn.jobstart(argv, {
      term = true,
      env = env,
      on_stdout = fm.capture_stdout and function(_, data)
        captured = (captured .. table.concat(data, "\n")):sub(-STDOUT_TAIL)
      end or nil,
      on_exit = function(_, status)
        finish(status)
      end,
    })
  end)

  if not started or job <= 0 then
    term:close()
    take(out.cwd_file)
    take(out.chooser_file)
    file_managers.report(("could not start %s: %s"):format(argv[1], started and ("jobstart() gave " .. job) or job))
  end
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

        return
      end

      -- Snacks opens the dashboard on UIEnter (none headless); the explorer comes after it. Snacks' own handling of a
      -- directory argument is not left to do this: under Neovide the argument became a second buffer that no window
      -- showed, and no explorer opened.
      vim.api.nvim_create_autocmd("UIEnter", {
        once = true,
        callback = function()
          vim.schedule(function()
            show_new_folder(false)
          end)
        end,
      })
    end,
  })
end

return M
