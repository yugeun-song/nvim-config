local M = {}

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

local history = vim.fn.stdpath("state") .. "/open_folder_history"

function M.recent()
  local ok, dirs = pcall(vim.fn.readfile, history)
  return vim.tbl_filter(function(dir)
    return vim.fn.isdirectory(dir) == 1
  end, ok and dirs or {})
end

local function remember(dir)
  local dirs = { vim.fs.normalize(dir) }
  for _, old in ipairs(M.recent()) do
    if old ~= dirs[1] and #dirs < 50 then
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
  if session_exists() then
    require("persistence").load()
  elseif #files == 0 then
    Snacks.dashboard({ buf = current, win = vim.api.nvim_get_current_win() })
  end
  for _, file in ipairs(files) do
    vim.cmd.edit(vim.fn.fnameescape(file))
  end
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
      keys = { q = "close" },
    },
  })
  term:on("TermClose", function()
    local status = vim.v.event.status
    term:close()
    vim.schedule(function()
      if status ~= 0 then
        vim.notify("yazi exited with code " .. status, vim.log.levels.ERROR, { title = "Open Folder" })
      end
      local dir, files = take(cwd_file)[1], take(chooser_file)
      if files[1] then
        dir = vim.fs.root(files[1], ".git") or vim.fs.dirname(files[1])
      end
      if dir and (files[1] or vim.fs.normalize(dir) ~= vim.fs.normalize(vim.fn.getcwd())) then
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
    if vim.fs.normalize(vim.api.nvim_buf_get_name(buf)) == vim.fs.normalize(dir) then
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
