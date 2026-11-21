-- Windows: npm installs a program as a .cmd (npm's cmd-shim) that runs `node <script>`, and Mason puts a .cmd of its own
-- in front of it; through either, cmd.exe reads the program's arguments as its own syntax. Following the two gives node
-- and the script, so a caller can start node itself. A .cmd that does anything else is not followed.
local M = {}

local uv = vim.uv
local cache = {}

local function last_line(path)
  local f = io.open(path, "rb")

  if not f then
    return ""
  end

  local text = f:read(16384) or ""

  f:close()

  local line = ""

  for each in vim.gsplit(text, "\r?\n") do
    if each:find("%S") then
      line = each
    end
  end

  return line
end

-- Whether path, resolved, lies inside dir, resolved.
local function inside(path, dir)
  local p, d = uv.fs_realpath(path), uv.fs_realpath(dir)

  return p ~= nil and d ~= nil and vim.startswith(p:lower(), d:lower():gsub("[\\/]$", "") .. "\\")
end

---@return { node: string, script: string }?
local function follow(cmd, depth)
  local dir = vim.fs.dirname(cmd)
  local line = last_line(cmd)
  -- npm's cmd-shim ends with "%_prog%"  "%dp0%\..\<package>\<script>" %*, %_prog% being the node.exe beside it, else
  -- node.
  local script = line:match([["%%_prog%%"%s+"%%dp0%%\([^"]+)" %%%*%s*$]])

  if script then
    script = vim.fs.joinpath(dir, script)

    local node = vim.fs.joinpath(dir, "node.exe")

    node = uv.fs_stat(node) and node or vim.fn.exepath("node")

    -- The package's own script, under the node_modules the launcher serves.
    if inside(script, vim.fs.dirname(dir)) and node:lower():find("%.exe$") then
      return { node = node, script = assert(uv.fs_realpath(script)) }
    end

    return nil
  end

  -- Mason's ends with "%dp0%\..\packages\<name>\node_modules\.bin\<program>.cmd" %*.
  local target = line:match([["%%dp0%%\([^"]+%.[cC][mM][dD])" %%%*%s*$]])

  return target and depth == 0 and M.resolve(vim.fs.joinpath(dir, target), depth + 1) or nil
end

-- node and the script an npm .cmd runs, through Mason's .cmd in front of it; nil for anything else. Kept per file until
-- the file changes.
---@param cmd string? a path, as exepath() gives it
---@return { node: string, script: string }?
function M.resolve(cmd, depth)
  depth = depth or 0

  if type(cmd) ~= "string" or not cmd:lower():find("%.cmd$") then
    return nil
  end

  local st = uv.fs_stat(cmd)

  if not st or st.type ~= "file" then
    return nil
  end

  local key = cmd:lower()
  local hit = cache[key]

  if hit and hit.mtime == st.mtime.sec and hit.size == st.size then
    return hit.result or nil
  end

  local result = follow(cmd, depth)

  cache[key] = { mtime = st.mtime.sec, size = st.size, result = result or false }

  return result
end

return M
