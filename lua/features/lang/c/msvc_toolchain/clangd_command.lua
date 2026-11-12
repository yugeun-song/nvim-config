-- A project's cl command lines, as MSBuild gives them, as compile_commands.json entries clangd reads the way the
-- build compiles: the project's own target and system include directories instead of whatever environment Neovim
-- happens to have. Nothing here runs a program or reads a file.
local M = {}

-- argv[0] when the project names no compiler: the name alone makes clangd read the options as cl's. Either way it
-- is never run: clangd executes a driver only when --query-driver allows its path, and lua/features/lang/c/clangd.lua
-- allows only the directories of the gcc and clang on PATH.
local DRIVER = "cl.exe"

-- A command line split as cl's runtime and clangd split it (the Windows rules): a backslash is literal unless a
-- double quote follows; 2n backslashes and a quote are n backslashes and a quote that opens or closes; 2n+1 are n
-- backslashes and a literal quote; "" inside quotes is a literal quote.
---@param text string
---@return string[]
function M.split(text)
  local args, buf, quoted, i, n = {}, nil, false, 1, #text

  local function put(s)
    buf = buf or {}
    buf[#buf + 1] = s
  end

  while i <= n do
    local stop = text:find('[\\" \t\r\n]', i)

    if not stop then
      put(text:sub(i))

      break
    end

    if stop > i then
      put(text:sub(i, stop - 1))
    end

    local c = text:sub(stop, stop)

    i = stop + 1
    if c == "\\" then
      local last = text:find("[^\\]", stop) or (n + 1)
      local count = last - stop

      if text:sub(last, last) == '"' then
        put(("\\"):rep(math.floor(count / 2)))
        if count % 2 == 1 then
          put('"')
          last = last + 1
        end
      else
        put(("\\"):rep(count))
      end

      i = last
    elseif c == '"' then
      if quoted and text:sub(i, i) == '"' then
        put('"')
        i = i + 1
      else
        quoted = not quoted
        buf = buf or {}
      end
    elseif quoted then
      put(c)
    elseif buf then
      args[#args + 1] = table.concat(buf)
      buf = nil
    end
  end

  if buf then
    args[#args + 1] = table.concat(buf)
  end

  return args
end

local function is_switch(arg, name)
  local lead = arg:sub(1, 1)

  return (lead == "/" or lead == "-") and arg:sub(2) == name
end

-- cl's /external:W1..W4 sets a warning level for external headers; clang-cl reads each as -Wsystem-headers,
-- which makes it warn inside the Windows SDK (clangd then shows a stray note on line 1). W0 is left as written.
local function is_external_warning_level(arg)
  return arg:find("^[/-]external:W[1-4]$") ~= nil
end

local function names_a_target(arg)
  return arg:find("^%-%-target=") ~= nil or arg == "-target" or arg == "--target" or arg == "-m32" or arg == "-m64"
end

---@class MsvcProjectFacts
---@field driver string? the compiler the project builds with (a full path to cl.exe or clang-cl.exe)
---@field target string? the clang target switch Microsoft's targets define for the project's platform
---@field system_includes string[]? the project's include directories a build passes through INCLUDE

-- The entries of one GetClCommandLines item: its switches serve every file it lists.
---@param item { Identity: string, Files: string?, WorkingDirectory: string? }
---@param project MsvcProjectFacts
---@return { directory: string, file: string, arguments: string[] }[]
function M.entries(item, project)
  local switches, ignores_standard_includes, has_target = {}, false, false

  for _, arg in ipairs(M.split(item.Identity or "")) do
    if not is_external_warning_level(arg) then
      switches[#switches + 1] = arg
      ignores_standard_includes = ignores_standard_includes or is_switch(arg, "X")
      has_target = has_target or names_a_target(arg)
    end
  end

  local head = { project.driver or DRIVER }

  if project.target and project.target ~= "" and not has_target then
    head[#head + 1] = project.target
  end

  -- /X is the project's IgnoreStandardIncludePath: cl then leaves INCLUDE out, and so do these.
  if not ignores_standard_includes then
    for _, dir in ipairs(project.system_includes or {}) do
      head[#head + 1] = "/imsvc"
      head[#head + 1] = dir
    end
  end

  local entries = {}

  for _, file in ipairs(vim.split(item.Files or "", ";", { plain = true, trimempty = true })) do
    local arguments = vim.list_extend(vim.list_extend({}, head), switches)

    arguments[#arguments + 1] = file
    entries[#entries + 1] = { directory = item.WorkingDirectory, file = file, arguments = arguments }
  end

  return entries
end

-- A ";" list of directories as MSBuild writes one (empty items, repeats, a trailing separator), in order, each
-- once.
---@param ... string?
---@return string[]
function M.directories(...)
  local dirs, seen = {}, {}

  for n = 1, select("#", ...) do
    for dir in vim.gsplit(select(n, ...) or "", ";", { plain = true, trimempty = true }) do
      dir = vim.trim(dir)

      local key = dir:lower():gsub("[\\/]+$", "")

      if dir ~= "" and not seen[key] then
        seen[key] = true
        dirs[#dirs + 1] = dir
      end
    end
  end

  return dirs
end

return M
