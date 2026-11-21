-- persistence.nvim's sessions are Vimscript that :mksession writes and :source runs. :mksession writes a line break in
-- a buffer's name as a backslash and a line break, and :source runs what follows as a command of its own: a file a
-- repository names so (on Linux and macOS) put a command into the session once it was opened, which Open Folder, the
-- dashboard and <leader>qs then ran. No session is written while a buffer's name holds a control character, and a
-- session with a line that ends in a backslash, which :mksession does not otherwise write, is not read. persistence
-- names the session file after the working directory and runs ":mks! <file>" and ":source <file>" as one string, in
-- which a line break of that name starts a command: no session is written or read under a name with one either.
local M = {}

local function named_badly()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)

    if name:find("%c") then
      return name
    end
  end
end

-- Whether a session file holds a line ending in an odd number of backslashes.
function M.broken(path)
  local f = io.open(path, "rb")

  if not f then
    return false
  end

  for line in f:lines() do
    local tail = line:gsub("\r$", ""):match("\\+$")

    if tail and #tail % 2 == 1 then
      f:close()

      return true
    end
  end

  f:close()

  return false
end

local installed = false

function M.install()
  local ok, persistence = pcall(require, "persistence")

  if installed or not ok then
    return
  end

  installed = true

  local save, load = persistence.save, persistence.load

  ---@diagnostic disable-next-line: duplicate-set-field
  persistence.save = function(...)
    local name = named_badly()
    local file = persistence.current()

    if name or file:find("%c") then
      vim.notify(
        name and ("The session is not saved: a buffer's name holds a control character (%q)"):format(name)
          or ("The session is not saved: its file name holds a control character (%q)"):format(file),
        vim.log.levels.WARN
      )

      return
    end

    return save(...)
  end

  ---@diagnostic disable-next-line: duplicate-set-field
  persistence.load = function(opts)
    local file

    if opts and opts.last then
      file = persistence.last()
    else
      file = persistence.current()

      if vim.fn.filereadable(file) == 0 then
        file = persistence.current({ branch = false })
      end
    end

    if file and file:find("%c") then
      vim.notify(
        ("The session is not loaded: its file name holds a control character (%q)"):format(file),
        vim.log.levels.ERROR
      )

      return
    end

    if file and M.broken(file) then
      vim.notify(
        ("%s is not loaded: a line in it ends in a backslash, as a file name with a line break leaves it"):format(file),
        vim.log.levels.ERROR
      )

      return
    end

    return load(opts)
  end
end

return M
