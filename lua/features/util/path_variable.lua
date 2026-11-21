-- PATH with absolute directories only. An empty entry (a separator at either end, two in a row) or a relative one
-- names the current directory: Neovim's own lookups (Vimscript executable() and exepath(), jobstart(), :terminal, the
-- clipboard provider) and, on Linux and macOS, execvp() would run a program a repository put there, even with
-- Windows' NoDefaultCurrentDirectoryInExePath set (init.lua). On Linux and macOS a leading ~ is the home directory:
-- a quoted ~ reaches PATH as it is, where bash finds commands but execvp() and Neovim do not.
local M = {}

local WIN = vim.fn.has("win32") == 1

M.SEP = WIN and ";" or ":"

local function absolute(dir)
  if WIN then
    -- A drive path or a UNC path, possibly quoted as cmd.exe accepts it.
    return dir:match('^"?%a:[/\\]') ~= nil or dir:match('^"?[/\\][/\\]') ~= nil
  end

  return dir:sub(1, 1) == "/"
end

local function home_expanded(dir)
  if not WIN and (dir == "~" or dir:sub(1, 2) == "~/") then
    local home = vim.uv.os_homedir()

    if home and home ~= "" then
      return home .. dir:sub(2)
    end
  end

  return dir
end

function M.clean(path)
  local kept = {}

  for dir in vim.gsplit(path or "", M.SEP, { plain = true }) do
    dir = home_expanded(dir)

    if vim.trim(dir) ~= "" and absolute(vim.trim(dir)) then
      kept[#kept + 1] = dir
    end
  end

  return table.concat(kept, M.SEP)
end

-- path with dir after it, never leaving an empty entry; a dir that is not absolute is left out.
function M.append(path, dir)
  path = path or ""

  if type(dir) ~= "string" or not absolute(vim.trim(dir)) then
    return path
  end

  if path == "" then
    return dir
  end

  return (path:sub(-1) == M.SEP and path or path .. M.SEP) .. dir
end

-- Cleans this Neovim's PATH, once at startup; what it starts inherits it.
function M.clean_environment()
  local path = vim.uv.os_getenv("PATH")

  if path then
    local clean = M.clean(path)

    if clean ~= path then
      vim.uv.os_setenv("PATH", clean)
    end
  end
end

return M
