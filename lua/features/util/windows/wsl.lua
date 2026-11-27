-- Windows only at runtime: connect host Windows Neovim or Neovide to Neovim inside WSL via
-- native/windows_wsl_bridge.c (no shell, no TCP, owner-only Named Pipe for TUI, stdio pipes for Neovide).
-- Pure parsers and validators are also exposed for cross-platform unit tests.
local M = {}

local uv = vim.uv
local WIN = vim.fn.has("win32") == 1
local MAX_DISTRO_BYTES = 128
local MAX_LINUX_PATH_BYTES = 4096

local SCRIPT = vim.fs.joinpath(
  vim.fs.normalize(debug.getinfo(1, "S").source:sub(2)):match("^(.*)/lua/") or vim.fn.stdpath("config"),
  "scripts",
  "wsl.lua"
)

local function has_control(text)
  return text:find("[%z\1-\31\127]") ~= nil
end

function M.validate_distro(name)
  if type(name) ~= "string" or name == "" or #name > MAX_DISTRO_BYTES then
    return false
  end

  if name:sub(1, 1) == "-" or name:sub(1, 1) == " " or name:sub(-1) == " " then
    return false
  end

  return name:match("^[%w%._%-% ]+$") ~= nil
end

function M.validate_linux_dir(dir)
  if type(dir) ~= "string" or dir == "" or #dir > MAX_LINUX_PATH_BYTES or has_control(dir) then
    return false
  end

  return dir == "~" or dir:sub(1, 1) == "/"
end

function M.validate_linux_nvim(bin)
  if type(bin) ~= "string" or bin == "" or #bin > MAX_LINUX_PATH_BYTES or has_control(bin) then
    return false
  end

  if bin == "nvim" then
    return true
  end

  if bin:sub(1, 1) ~= "/" or bin:find("[ \t]") then
    return false
  end

  return not bin:find("/../", 1, true) and not bin:match("/%.%.$")
end

function M.validate_linux_file(path)
  return type(path) == "string" and path ~= "" and #path <= MAX_LINUX_PATH_BYTES and not has_control(path)
end

function M.validate_local_exe(path, expected_name)
  if type(path) ~= "string" or path == "" or has_control(path) then
    return false
  end

  if not path:match("^%a:[/\\]") or path:find(":", 3, true) then
    return false
  end

  if expected_name and vim.fs.basename((path:gsub("\\", "/"))):lower() ~= expected_name:lower() then
    return false
  end

  if WIN then
    local st = uv.fs_stat(path)

    if not st or st.type ~= "file" then
      return false
    end

    local real = uv.fs_realpath(path)

    if not real or not real:match("^%a:[/\\]") then
      return false
    end
  end

  return true
end

local reg_declared = false
local advapi32

local function ensure_registry_ffi()
  local ffi = require("ffi")

  if not reg_declared then
    reg_declared = true
    for _, decl in ipairs({
      "int32_t RegOpenKeyExW(void *, const uint16_t *, uint32_t, uint32_t, void **);",
      "int32_t RegEnumKeyExW(void *, uint32_t, uint16_t *, uint32_t *, uint32_t *, uint16_t *, uint32_t *, void *);",
      "int32_t RegQueryValueExW(void *, const uint16_t *, uint32_t *, uint32_t *, uint8_t *, uint32_t *);",
      "int32_t RegCloseKey(void *);",
      "uint32_t GetSystemDirectoryW(uint16_t *, uint32_t);",
      "int MultiByteToWideChar(uint32_t, uint32_t, const char *, int, uint16_t *, int);",
      "int WideCharToMultiByte(uint32_t, uint32_t, const uint16_t *, int, char *, int, const char *, int *);",
    }) do
      pcall(ffi.cdef, decl)
    end

    advapi32 = ffi.load("advapi32")
  end

  return ffi, advapi32
end

local function system_directory()
  local ok, dir = pcall(function()
    local ffi = ensure_registry_ffi()
    local buf = ffi.new("uint16_t[260]")
    local len = ffi.C.GetSystemDirectoryW(buf, 260)

    if len <= 0 or len >= 260 then
      return nil
    end

    local out = ffi.new("char[?]", len * 4 + 1)
    local n = ffi.C.WideCharToMultiByte(65001, 0, buf, len, out, len * 4 + 1, nil, nil)

    return n > 0 and ffi.string(out, n) or nil
  end)

  if ok and type(dir) == "string" and dir ~= "" then
    return dir
  end

  local root = vim.env.SystemRoot

  if type(root) == "string" and root ~= "" then
    return vim.fs.joinpath(root, "System32")
  end

  return "C:\\Windows\\System32"
end

function M.wsl_exe()
  if not WIN then
    return nil
  end

  local exe = vim.fs.joinpath(system_directory(), "wsl.exe")

  return M.validate_local_exe(exe, "wsl.exe") and exe or nil
end

-- Reads HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss in-process (~0.05 ms, zero subprocesses) to determine
-- whether WSL has installed distributions without spawning wsl.exe at startup.
function M.registry_distros()
  if not WIN then
    return {}
  end

  local ok, result = pcall(function()
    local ffi, reg = ensure_registry_ffi()
    local CP_UTF8 = 65001
    local KEY_READ = 0x20019
    local REG_SZ = 1
    local REG_DWORD = 4
    local HKEY_CURRENT_USER = ffi.cast("void *", ffi.cast("intptr_t", ffi.cast("int32_t", 0x80000001)))

    local function to_wide(text)
      local n = ffi.C.MultiByteToWideChar(CP_UTF8, 0, text, #text, nil, 0)
      local buf = ffi.new("uint16_t[?]", n + 1)

      ffi.C.MultiByteToWideChar(CP_UTF8, 0, text, #text, buf, n)
      buf[n] = 0

      return buf
    end

    local function from_wide(wbuf, wchar_count)
      local n = ffi.C.WideCharToMultiByte(CP_UTF8, 0, wbuf, wchar_count, nil, 0, nil, nil)

      if n <= 0 then
        return ""
      end

      local out = ffi.new("char[?]", n)

      ffi.C.WideCharToMultiByte(CP_UTF8, 0, wbuf, wchar_count, out, n, nil, nil)

      return ffi.string(out, n):gsub("%z.*$", "")
    end

    local function query_sz(hkey, name)
      local kind = ffi.new("uint32_t[1]")
      local size = ffi.new("uint32_t[1]", 1024)
      local buf = ffi.new("uint8_t[1024]")

      if reg.RegQueryValueExW(hkey, to_wide(name), nil, kind, buf, size) ~= 0 or kind[0] ~= REG_SZ then
        return nil
      end

      local wcount = math.floor(size[0] / 2)

      if wcount <= 0 then
        return ""
      end

      return from_wide(ffi.cast("const uint16_t *", buf), wcount)
    end

    local function query_dword(hkey, name)
      local kind = ffi.new("uint32_t[1]")
      local size = ffi.new("uint32_t[1]", 4)
      local buf = ffi.new("uint32_t[1]")

      if reg.RegQueryValueExW(hkey, to_wide(name), nil, kind, ffi.cast("uint8_t *", buf), size) ~= 0 then
        return nil
      end

      if kind[0] ~= REG_DWORD or size[0] ~= 4 then
        return nil
      end

      return tonumber(buf[0])
    end

    local lxss = ffi.new("void *[1]")

    if
      reg.RegOpenKeyExW(
        HKEY_CURRENT_USER,
        to_wide([[Software\Microsoft\Windows\CurrentVersion\Lxss]]),
        0,
        KEY_READ,
        lxss
      ) ~= 0
    then
      return {}
    end

    local default_guid = query_sz(lxss[0], "DefaultDistribution")
    local list = {}
    local name_buf = ffi.new("uint16_t[256]")
    local name_len = ffi.new("uint32_t[1]")

    for idx = 0, 63 do
      name_len[0] = 256
      if reg.RegEnumKeyExW(lxss[0], idx, name_buf, name_len, nil, nil, nil, nil) ~= 0 then
        break
      end

      local subkey_name = from_wide(name_buf, tonumber(name_len[0]) or 0)
      local sub = ffi.new("void *[1]")

      if reg.RegOpenKeyExW(lxss[0], name_buf, 0, KEY_READ, sub) == 0 then
        local distro = query_sz(sub[0], "DistributionName")
        local state = query_dword(sub[0], "State")
        local version = query_dword(sub[0], "Version")

        reg.RegCloseKey(sub[0])
        if distro and M.validate_distro(distro) and (state == nil or state == 1) then
          list[#list + 1] = {
            name = distro,
            default = default_guid ~= nil and subkey_name:lower() == default_guid:lower(),
            version = version or 2,
          }
        end
      end
    end

    reg.RegCloseKey(lxss[0])

    return list
  end)

  return ok and type(result) == "table" and result or {}
end

function M.is_available()
  if not WIN or not M.wsl_exe() then
    return false
  end

  return #M.registry_distros() > 0
end

local function encode_utf8(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 64), 0x80 + (cp % 64))
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + (math.floor(cp / 64) % 64), 0x80 + (cp % 64))
  else
    return string.char(
      0xF0 + math.floor(cp / 262144),
      0x80 + (math.floor(cp / 4096) % 64),
      0x80 + (math.floor(cp / 64) % 64),
      0x80 + (cp % 64)
    )
  end
end

-- Decodes UTF-16LE without vim.iconv, which crashes Neovim on Win32 on unpaired surrogates or truncated bytes.
local function decode_utf16le(bytes)
  local out = {}
  local len = #bytes
  local i = 1

  while i <= len - 1 do
    local b1, b2 = bytes:byte(i, i + 1)
    local u = b1 + b2 * 256

    i = i + 2
    if u >= 0xD800 and u <= 0xDBFF then
      if i <= len - 1 then
        local c1, c2 = bytes:byte(i, i + 1)
        local u2 = c1 + c2 * 256

        if u2 >= 0xDC00 and u2 <= 0xDFFF then
          i = i + 2

          local cp = 0x10000 + (u - 0xD800) * 1024 + (u2 - 0xDC00)

          out[#out + 1] = encode_utf8(cp)
        else
          out[#out + 1] = "\239\191\189"
        end
      else
        out[#out + 1] = "\239\191\189"
      end
    elseif u >= 0xDC00 and u <= 0xDFFF then
      out[#out + 1] = "\239\191\189"
    elseif u ~= 0 then
      out[#out + 1] = encode_utf8(u)
    end
  end

  if i == len then
    out[#out + 1] = "\239\191\189"
  end

  return table.concat(out)
end

-- Parses `wsl.exe --list --verbose` output (handles UTF-16LE + BOM and localized headers).
function M.parse_distro_list(raw)
  if type(raw) ~= "string" or raw == "" then
    return {}
  end

  local text = raw

  if text:sub(1, 2) == "\255\254" or text:find("\0", 1, true) then
    if text:sub(1, 2) == "\255\254" then
      text = text:sub(3)
    end

    text = decode_utf16le(text)
  end

  text = text:gsub("^\239\187\191", "")

  local distros = {}

  for line in vim.gsplit(text, "\r?\n", { trimempty = true }) do
    local star, body, state, ver = line:match("^%s*(%*?)%s*(.-)%s%s+(.-)%s%s+(%d+)%s*$")

    if not body then
      star, body, state, ver = line:match("^%s*(%*?)%s*(.+)%s+(%S+)%s+(%d+)%s*$")
    end

    if body and ver then
      local name = vim.trim(body)

      if M.validate_distro(name) then
        distros[#distros + 1] = {
          name = name,
          default = star == "*",
          state = vim.trim(state),
          version = tonumber(ver),
        }
      end
    end
  end

  return distros
end

function M.default_distro(distros)
  for _, d in ipairs(distros or {}) do
    if d.default then
      return d.name
    end
  end

  return distros and distros[1] and distros[1].name or nil
end

function M.list_distros(cb)
  local wsl = M.wsl_exe()

  if not wsl then
    return cb({}, "System32\\wsl.exe was not found")
  end

  local ok, err = pcall(vim.system, { wsl, "--list", "--verbose" }, {
    text = false,
    timeout = 5000,
    env = { WSL_UTF8 = "1" },
  }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        local msg = vim.trim((res.stderr or ""):gsub("\0", ""))

        cb({}, msg ~= "" and msg or ("wsl.exe --list exited with code " .. tostring(res.code)))
      else
        cb(M.parse_distro_list(res.stdout or ""), nil)
      end
    end)
  end)

  if not ok then
    cb({}, tostring(err))
  end
end

function M.list_distros_sync()
  local wsl = M.wsl_exe()

  if not wsl then
    return {}, "System32\\wsl.exe was not found"
  end

  local ok, res = pcall(function()
    local proc = vim.system({ wsl, "--list", "--verbose" }, {
      text = false,
      timeout = 5000,
      env = { WSL_UTF8 = "1" },
    })

    return proc:wait()
  end)

  if not ok or not res then
    return {}, tostring(res)
  end

  if res.code ~= 0 then
    local msg = vim.trim((res.stderr or ""):gsub("\0", ""))

    return {}, msg ~= "" and msg or ("wsl.exe --list exited with code " .. tostring(res.code))
  end

  return M.parse_distro_list(res.stdout or ""), nil
end

function M.helper_env()
  if not WIN then
    return {}
  end

  local helper = require("features.util.windows.ime_helper").path({ build = false })

  if not helper or not M.validate_local_exe(helper) then
    return {}
  end

  return {
    NVIM_WSL_HOST_HELPER_DIR = (vim.fs.dirname(helper):gsub("/", "\\")),
    NVIM_WSL_HOST_HELPER_EXE = vim.fs.basename(helper),
  }
end

local function validate_connect_opts(opts)
  if type(opts) ~= "table" then
    return nil, "invalid WSL connection options"
  end

  local distro = opts.distro
  local dir = opts.dir or "~"
  local nvim_bin = opts.nvim or "nvim"
  local files = opts.files or {}

  if not M.validate_distro(distro) then
    return nil, "invalid WSL distribution name: " .. tostring(distro)
  end

  if not M.validate_linux_dir(dir) then
    return nil, "WSL directory must be ~ or an absolute Linux path starting with /"
  end

  if not M.validate_linux_nvim(nvim_bin) then
    return nil, "invalid WSL nvim binary path: " .. tostring(nvim_bin)
  end

  for _, file in ipairs(files) do
    if not M.validate_linux_file(file) then
      return nil, "invalid file argument for WSL"
    end
  end

  return {
    distro = distro,
    dir = dir,
    nvim = nvim_bin,
    files = files,
    mode = opts.mode,
  }
end

function M.find_neovide()
  local exe = vim.fn.exepath("neovide")

  if exe == "" then
    return nil
  end

  return M.validate_local_exe(exe, "neovide.exe") and exe or nil
end

function M.find_wt()
  local exe = vim.fn.exepath("wt.exe")

  if exe == "" then
    exe = vim.fn.exepath("wt")
  end

  if exe == "" then
    return nil
  end

  return M.validate_local_exe(exe, "wt.exe") and exe or nil
end

function M.build_gui_launch(bridge_exe, opts)
  local clean, why = validate_connect_opts(opts)

  if not clean then
    return nil, nil, why
  end

  if not M.validate_local_exe(bridge_exe) then
    return nil, nil, "invalid windows_wsl_bridge executable"
  end

  local neovide = opts.neovide_exe or M.find_neovide()

  if not neovide or not M.validate_local_exe(neovide, "neovide.exe") then
    return nil, nil, "neovide.exe is not on PATH"
  end

  local argv = {
    (neovide:gsub("/", "\\")),
    "--no-fork",
    "--neovim-bin",
    (bridge_exe:gsub("/", "\\")),
  }

  if #clean.files > 0 then
    -- First -- hands remaining arguments to the bridge; second -- marks positional files inside ValidateForwardedEmbedArgs.
    argv[#argv + 1] = "--"
    argv[#argv + 1] = "--"
    for _, file in ipairs(clean.files) do
      argv[#argv + 1] = file
    end
  end

  local env = vim.tbl_extend("force", {
    NVIM_WSL_DISTRO = clean.distro,
    NVIM_WSL_DIR = clean.dir,
    NVIM_WSL_NVIM = clean.nvim,
  }, opts.helper_env or M.helper_env())

  return argv, env, nil
end

-- Encodes paths in base64 and strips/forbids ';' in every argument so wt.exe cannot split subcommands.
function M.build_wt_command(host_nvim, script_path, opts)
  local clean, why = validate_connect_opts(opts)

  if not clean then
    return nil, why
  end

  if not M.validate_local_exe(host_nvim, "nvim.exe") then
    return nil, "invalid host nvim.exe path"
  end

  if type(script_path) ~= "string" or not script_path:match("^%a:[/\\]") or has_control(script_path) then
    return nil, "invalid scripts/wsl.lua path"
  end

  local wt = opts.wt_exe or M.find_wt()

  if not wt or not M.validate_local_exe(wt, "wt.exe") then
    return nil, "wt.exe is not available"
  end

  local argv = {
    (wt:gsub("/", "\\")),
    "-w",
    "0",
    "new-tab",
    "--title",
    "WSL: " .. clean.distro,
    "--",
    (host_nvim:gsub("/", "\\")),
    "-l",
    (script_path:gsub("/", "\\")),
    "--tui",
    "--distro",
    clean.distro,
    "--dir-b64",
    vim.base64.encode(clean.dir),
    "--nvim",
    clean.nvim,
  }

  for _, file in ipairs(clean.files) do
    argv[#argv + 1] = "--file-b64"
    argv[#argv + 1] = vim.base64.encode(file)
  end

  for _, part in ipairs(argv) do
    if part:find(";", 1, true) or has_control(part) then
      return nil, "wt.exe argument holds ';' or a control character"
    end
  end

  return argv, nil
end

function M.build_spawn_console_args(bridge_exe, host_nvim, script_path, opts)
  local clean, why = validate_connect_opts(opts)

  if not clean then
    return nil, why
  end

  if not M.validate_local_exe(bridge_exe) or not M.validate_local_exe(host_nvim, "nvim.exe") then
    return nil, "invalid bridge or host nvim executable"
  end

  local argv = {
    (bridge_exe:gsub("/", "\\")),
    "spawn-console",
    (host_nvim:gsub("/", "\\")),
    (script_path:gsub("/", "\\")),
    "--tui",
    "--distro",
    clean.distro,
    "--dir-b64",
    vim.base64.encode(clean.dir),
    "--nvim",
    clean.nvim,
  }

  for _, file in ipairs(clean.files) do
    argv[#argv + 1] = "--file-b64"
    argv[#argv + 1] = vim.base64.encode(file)
  end

  return argv, nil
end

local function launch_with_bridge(bridge_exe, clean, cb)
  if clean.mode == "gui" then
    local argv, env, err = M.build_gui_launch(bridge_exe, clean)

    if not argv then
      return cb(false, err)
    end

    local ok, proc = pcall(vim.system, argv, { detach = true, env = env })

    if not ok or not proc then
      return cb(false, "could not start neovide: " .. tostring(proc))
    end

    return cb(true)
  end

  local host_nvim = vim.v.progpath

  if not M.validate_local_exe(host_nvim, "nvim.exe") then
    return cb(false, "cannot determine host nvim.exe path")
  end

  local wt_argv = M.build_wt_command(host_nvim, SCRIPT, clean)

  if wt_argv then
    local ok, proc = pcall(vim.system, wt_argv, { detach = true })

    if ok and proc then
      return cb(true)
    end
  end

  local sc_argv, sc_err = M.build_spawn_console_args(bridge_exe, host_nvim, SCRIPT, clean)

  if not sc_argv then
    return cb(false, sc_err)
  end

  local ok, started = pcall(vim.system, sc_argv, { text = true, timeout = 5000 }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        cb(false, vim.trim(res.stderr or "") ~= "" and vim.trim(res.stderr) or ("spawn-console exit " .. res.code))
      else
        cb(true)
      end
    end)
  end)

  if not ok then
    cb(false, tostring(started))
  end
end

function M.default_mode(has_neovide)
  if has_neovide == nil then
    has_neovide = M.find_neovide() ~= nil
  end

  return (vim.g.neovide and has_neovide) and "gui" or "tui"
end

function M.connect(opts, cb)
  cb = cb
    or function(ok, err)
      if not ok and err then
        vim.notify(err, vim.log.levels.ERROR, { title = "WSL" })
      end
    end

  if not WIN then
    return cb(false, "WSL connection is only supported on Windows")
  end

  if not M.wsl_exe() then
    return cb(false, "System32\\wsl.exe was not found")
  end

  local clean, why = validate_connect_opts(opts)

  if not clean then
    return cb(false, why)
  end

  local reg_distros = M.registry_distros()

  if #reg_distros > 0 then
    local found = false

    for _, d in ipairs(reg_distros) do
      if d.name == clean.distro then
        found = true
        break
      end
    end

    if not found then
      return cb(false, "WSL distribution not found: " .. clean.distro)
    end
  end

  clean.mode = clean.mode or M.default_mode()
  if clean.mode ~= "gui" and clean.mode ~= "tui" then
    return cb(false, "WSL mode must be gui or tui")
  end

  if clean.mode == "gui" and not M.find_neovide() then
    return cb(false, "neovide.exe is not installed; choose TUI mode or install Neovide")
  end

  local bridge = require("features.util.windows.wsl_bridge")
  local exe, bwhy = bridge.path()

  if exe then
    return launch_with_bridge(exe, clean, cb)
  end

  if not bridge.is_building() then
    return cb(false, bwhy or "windows_wsl_bridge is not available")
  end

  vim.notify("Building windows_wsl_bridge; WSL will open when it finishes...", vim.log.levels.INFO, { title = "WSL" })
  bridge.on_ready(function(built, err)
    if not built then
      return cb(false, err or "windows_wsl_bridge build failed")
    end

    launch_with_bridge(built, clean, cb)
  end)
end

function M.pick()
  if not WIN then
    return
  end

  M.list_distros(function(distros, list_err)
    if list_err and #distros == 0 then
      vim.notify(list_err, vim.log.levels.ERROR, { title = "WSL" })

      return
    end

    if #distros == 0 then
      vim.notify("No WSL distributions found", vim.log.levels.WARN, { title = "WSL" })

      return
    end

    local items = {}

    for _, d in ipairs(distros) do
      items[#items + 1] = {
        label = ("%-22s [%s%s, WSL%d]"):format(d.name, d.default and "default, " or "", d.state, d.version),
        distro = d.name,
      }
    end

    vim.ui.select(items, {
      prompt = "Connect to WSL",
      format_item = function(item)
        return item.label
      end,
    }, function(picked)
      if not picked then
        return
      end

      M.connect({ distro = picked.distro, dir = "~" })
    end)
  end)
end

-- :Wsl [gui|tui] [DISTRO [DIR [FILES...]]]
function M.command(fargs)
  if not fargs or #fargs == 0 then
    return M.pick()
  end

  local idx = 1
  local mode = nil

  if fargs[idx] == "gui" or fargs[idx] == "tui" then
    mode = fargs[idx]
    idx = idx + 1
  end

  local distro = fargs[idx]
  local dir = fargs[idx + 1] or "~"
  local files = vim.list_slice(fargs, idx + 2)

  local function run_with(chosen_distro)
    M.connect({ distro = chosen_distro, dir = dir, mode = mode, files = files })
  end

  if distro then
    return run_with(distro)
  end

  M.list_distros(function(distros, err)
    local def = M.default_distro(distros)

    if not def then
      vim.notify(err or "No default WSL distribution found", vim.log.levels.ERROR, { title = "WSL" })

      return
    end

    run_with(def)
  end)
end

function M.complete(_, line)
  local parts = vim.split(vim.trim(line), "%s+")
  local trailing = line:sub(-1):match("%s") ~= nil
  local index = trailing and #parts + 1 or #parts

  if index == 2 then
    local out = { "gui", "tui" }

    for _, d in ipairs(M.registry_distros()) do
      if not vim.list_contains(out, d.name) then
        out[#out + 1] = d.name
      end
    end

    return out
  elseif index == 3 and (parts[2] == "gui" or parts[2] == "tui") then
    local out = {}

    for _, d in ipairs(M.registry_distros()) do
      if not vim.list_contains(out, d.name) then
        out[#out + 1] = d.name
      end
    end

    return out
  end

  return {}
end

return M
