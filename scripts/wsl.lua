-- Standalone launcher from a Windows terminal: connects host Neovide (GUI) or host Neovim (TUI) to WSL.
-- Usage: nvim -l scripts/wsl.lua [--gui|--tui] [-d|--distro NAME] [--dir PATH] [--nvim PATH] [-- FILE...]
if vim.fn.has("win32") == 0 then
  io.stderr:write("wsl.lua: Windows only\n")
  os.exit(1)
end

local script_dir = vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(arg[0], ":p")))
local repo_root = vim.fs.dirname(script_dir)

package.path = vim.fs.joinpath(repo_root, "lua", "?.lua")
  .. ";"
  .. vim.fs.joinpath(repo_root, "lua", "?", "init.lua")
  .. ";"
  .. package.path

require("features.util.path_variable").clean_environment()
if not vim.uv.os_getenv("NoDefaultCurrentDirectoryInExePath") then
  vim.uv.os_setenv("NoDefaultCurrentDirectoryInExePath", "1")
end

local wsl = require("features.util.windows.wsl")
local wsl_bridge = require("features.util.windows.wsl_bridge")

local function die(msg, code)
  io.stderr:write("wsl.lua: " .. msg .. "\n")
  os.exit(code or 1)
end

local function usage()
  io.stdout:write(
    "usage: nvim -l scripts/wsl.lua [--gui|--tui] [-d|--distro NAME] [--dir PATH] [--nvim PATH] [-- FILE...]\n"
  )

  os.exit(0)
end

local mode, distro, dir, nvim_bin
local files = {}
local i = 1

while i <= #arg do
  local a = arg[i]

  if a == "--" then
    for j = i + 1, #arg do
      files[#files + 1] = arg[j]
    end

    break
  elseif a == "-h" or a == "--help" then
    usage()
  elseif a == "--gui" then
    mode = "gui"
  elseif a == "--tui" then
    mode = "tui"
  elseif a == "-d" or a == "--distro" then
    i = i + 1
    distro = arg[i] or die("missing value for " .. a, 2)
  elseif a == "--dir" then
    i = i + 1
    dir = arg[i] or die("missing value for --dir", 2)
  elseif a == "--dir-b64" then
    i = i + 1
    local raw = arg[i] or die("missing value for --dir-b64", 2)
    local ok, decoded = pcall(vim.base64.decode, raw)

    if not ok then
      die("invalid base64 for --dir-b64", 2)
    end

    dir = decoded
  elseif a == "--nvim" then
    i = i + 1
    nvim_bin = arg[i] or die("missing value for --nvim", 2)
  elseif a == "--file-b64" then
    i = i + 1
    local raw = arg[i] or die("missing value for --file-b64", 2)
    local ok, decoded = pcall(vim.base64.decode, raw)

    if not ok then
      die("invalid base64 for --file-b64", 2)
    end

    files[#files + 1] = decoded
  elseif a:sub(1, 1) == "-" then
    die("unknown option: " .. a, 2)
  else
    files[#files + 1] = a
  end

  i = i + 1
end

if not wsl.wsl_exe() then
  die("System32\\wsl.exe was not found")
end

dir = dir or "~"
nvim_bin = nvim_bin or "nvim"
mode = mode or (wsl.find_neovide() and "gui" or "tui")

local distros, list_err = wsl.list_distros_sync()

if not distro then
  distro = wsl.default_distro(distros)
  if not distro then
    die(list_err or "no WSL distribution found")
  end
elseif #distros > 0 then
  local found = false

  for _, d in ipairs(distros) do
    if d.name == distro then
      found = true
      break
    end
  end

  if not found then
    die("WSL distribution not found: " .. distro)
  end
end

if not wsl.validate_distro(distro) then
  die("invalid WSL distribution name: " .. distro, 2)
end

if not wsl.validate_linux_dir(dir) then
  die("WSL directory must be ~ or start with /", 2)
end

if not wsl.validate_linux_nvim(nvim_bin) then
  die("invalid WSL nvim binary: " .. nvim_bin, 2)
end

for _, f in ipairs(files) do
  if not wsl.validate_linux_file(f) then
    die("invalid file argument", 2)
  end
end

-- Load cached MSVC environment only if windows_wsl_bridge is not yet compiled.
if not wsl_bridge.path({ build = false }) then
  pcall(function()
    require("features.lang.c.msvc_toolchain.developer_environment").setup()
  end)

  if wsl_bridge.path({ build = false }) == nil then
    io.stderr:write("Building windows_wsl_bridge...\n")
  end
end

local bridge_exe, bridge_err = wsl_bridge.ensure_sync()

if not bridge_exe then
  die(bridge_err or "windows_wsl_bridge is not available")

  return
end

local helper_env = wsl.helper_env()

if mode == "gui" then
  local argv, env, gui_err = wsl.build_gui_launch(bridge_exe, {
    distro = distro,
    dir = dir,
    nvim = nvim_bin,
    files = files,
    helper_env = helper_env,
  })

  if not argv then
    die(gui_err or "cannot prepare Neovide launch")
  end

  local ok, proc = pcall(vim.system, argv, { detach = true, env = env })

  if not ok or not proc then
    die("could not start neovide: " .. tostring(proc))
  end

  os.exit(0)
end

-- TUI mode: launch windows_wsl_bridge run-tui directly inheriting the live console handles (no cmd.exe).
local host_nvim = vim.v.progpath

if not wsl.validate_local_exe(host_nvim, "nvim.exe") then
  die("cannot determine host nvim.exe path")
end

local ffi = require("ffi")

for _, decl in ipairs({
  [[typedef struct _WSL_STARTUPINFOW {
    uint32_t cb;
    void *lpReserved;
    void *lpDesktop;
    void *lpTitle;
    uint32_t dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
    uint16_t wShowWindow, cbReserved2;
    void *lpReserved2;
    void *hStdInput, *hStdOutput, *hStdError;
  } WSL_STARTUPINFOW;]],
  [[typedef struct _WSL_PROCESS_INFORMATION {
    void *hProcess;
    void *hThread;
    uint32_t dwProcessId;
    uint32_t dwThreadId;
  } WSL_PROCESS_INFORMATION;]],
  "int CreateProcessW(const uint16_t *, uint16_t *, void *, void *, int, uint32_t, void *, const uint16_t *, WSL_STARTUPINFOW *, WSL_PROCESS_INFORMATION *);",
  "uint32_t WaitForSingleObject(void *, uint32_t);",
  "int GetExitCodeProcess(void *, uint32_t *);",
  "int CloseHandle(void *);",
  "int MultiByteToWideChar(uint32_t, uint32_t, const char *, int, uint16_t *, int);",
}) do
  pcall(ffi.cdef, decl)
end

local function quote_win(s)
  if s ~= "" and not s:find('[ \t"]') then
    return s
  end

  local out = { '"' }
  local bs = 0

  for idx = 1, #s do
    local ch = s:sub(idx, idx)

    if ch == "\\" then
      bs = bs + 1
    elseif ch == '"' then
      out[#out + 1] = ("\\"):rep(bs * 2 + 1) .. '"'
      bs = 0
    else
      out[#out + 1] = ("\\"):rep(bs) .. ch
      bs = 0
    end
  end

  out[#out + 1] = ("\\"):rep(bs * 2) .. '"'

  return table.concat(out)
end

local function to_wide(text)
  local n = ffi.C.MultiByteToWideChar(65001, 0, text, #text, nil, 0)
  local buf = ffi.new("uint16_t[?]", n + 1)

  ffi.C.MultiByteToWideChar(65001, 0, text, #text, buf, n)
  buf[n] = 0

  return buf
end

for k, v in pairs(helper_env) do
  vim.uv.os_setenv(k, v)
end

local run_argv = {
  (bridge_exe:gsub("/", "\\")),
  "run-tui",
  distro,
  dir,
  nvim_bin,
  (host_nvim:gsub("/", "\\")),
}

if #files > 0 then
  run_argv[#run_argv + 1] = "--"
  for _, f in ipairs(files) do
    run_argv[#run_argv + 1] = f
  end
end

local cmdline_parts = {}

for _, part in ipairs(run_argv) do
  cmdline_parts[#cmdline_parts + 1] = quote_win(part)
end

---@class WslStartupInfo: ffi.cdata*
---@field cb integer
local si = ffi.new("WSL_STARTUPINFOW") --[[@as WslStartupInfo]]
---@class WslProcessInfo: ffi.cdata*
---@field hProcess ffi.cdata*
---@field hThread ffi.cdata*
local pi = ffi.new("WSL_PROCESS_INFORMATION") --[[@as WslProcessInfo]]

si.cb = assert(ffi.sizeof(si))
local started = ffi.C.CreateProcessW(
  to_wide(run_argv[1]),
  to_wide(table.concat(cmdline_parts, " ")),
  nil,
  nil,
  1,
  0,
  nil,
  nil,
  si,
  pi
)

if started == 0 then
  die("could not start windows_wsl_bridge run-tui")
end

ffi.C.WaitForSingleObject(pi.hProcess, 0xFFFFFFFF)

local code = ffi.new("uint32_t[1]")

ffi.C.GetExitCodeProcess(pi.hProcess, code)
ffi.C.CloseHandle(pi.hProcess)
ffi.C.CloseHandle(pi.hThread)
os.exit(tonumber(code[0]))
