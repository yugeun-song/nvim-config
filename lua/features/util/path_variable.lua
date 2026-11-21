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
    dir = vim.trim(dir)

    -- A drive path or a UNC path, possibly quoted as cmd.exe accepts it. A quote left open makes libuv read the rest of
    -- PATH as one directory.
    if select(2, dir:gsub('"', "")) % 2 == 1 then
      return false
    end

    return dir:match('^"?%a:[/\\]') ~= nil or dir:match('^"?[/\\][/\\]') ~= nil
  end

  -- As written: execvp() and Neovim read " /usr/bin" as a directory below the current one.
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

-- PATH's entries. Windows: cmd.exe and libuv read a quoted part as one directory, ; included, so ; splits only outside
-- quotes; split there, one half of "C:\a;b" kept without the other would leave a quote open.
local function entries(path)
  if not WIN then
    return vim.split(path, M.SEP, { plain = true })
  end

  local out, from, quoted = {}, 1, false

  for i = 1, #path do
    local c = path:sub(i, i)

    if c == '"' then
      quoted = not quoted
    elseif c == ";" and not quoted then
      out[#out + 1] = path:sub(from, i - 1)
      from = i + 1
    end
  end

  out[#out + 1] = path:sub(from)

  return out
end

function M.clean(path)
  local kept = {}

  for _, dir in ipairs(entries(path or "")) do
    dir = home_expanded(dir)

    if absolute(dir) then
      kept[#kept + 1] = dir
    end
  end

  return table.concat(kept, M.SEP)
end

-- path with dir after it, never leaving an empty entry; a dir that is not absolute, or holds the separator (which would
-- split it into entries, relative ones among them), is left out.
function M.append(path, dir)
  path = path or ""

  if type(dir) ~= "string" or dir:find(M.SEP, 1, true) or not absolute(dir) then
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
