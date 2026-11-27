-- Windows only: native/windows_wsl_bridge.c, built on demand into stdpath("data")/nvim-config/windows_wsl_bridge
-- by Visual Studio's cl or clang targeting MSVC (the source refuses anything else). Nothing runs at startup or on
-- Linux/macOS.
local M = {}

local uv = vim.uv

local WIN = vim.fn.has("win32") == 1

local SRC = vim.fs.joinpath(
  vim.fs.normalize(debug.getinfo(1, "S").source:sub(2)):match("^(.*)/lua/") or vim.fn.stdpath("config"),
  "native",
  "windows_wsl_bridge.c"
)

local DIR = vim.fs.normalize(require("features.util.storage").path("data", "windows_wsl_bridge"))
local EXE_NAME = "^windows_wsl_bridge%-%x+%-%x+%.exe$"
local BUILD_TIMEOUT_MS = 120000
local SELFTEST_TIMEOUT_MS = 5000
local RECHECK_MS = 2000
local RETRY_AFTER_S = 24 * 3600

local function cl_in_toolset()
  local dir = uv.os_getenv("VCToolsInstallDir")

  if not dir or dir == "" then
    return nil
  end

  local host = (uv.os_uname().machine or ""):lower():find("arm") and "Hostarm64" or "Hostx64"
  local cl = vim.fs.joinpath(dir, "bin", host, "x64", "cl.exe")
  local st = uv.fs_stat(cl)

  return st and st.type == "file" and cl or nil
end

local COMPILERS = {
  {
    name = "cl",
    version = "msvc",
    locate = cl_in_toolset,
    args = function(out, program)
      return {
        program,
        "/nologo",
        "/Fo" .. out:sub(1, -5) .. ".obj",
        "/O2",
        "/MT",
        "/W4",
        "/WX",
        "/sdl",
        "/guard:cf",
        "/Fe" .. out,
        SRC,
        "/link",
        "/WX",
        "/guard:cf",
        "/DEPENDENTLOADFLAG:0x800",
        "/CETCOMPAT",
      }
    end,
  },
  {
    name = "clang",
    version = "clang",
    locate = function()
      local clang = vim.fn.exepath("clang")

      return clang ~= "" and clang or nil
    end,
    args = function(out, program)
      return {
        program,
        "--target=x86_64-pc-windows-msvc",
        "-O2",
        "-fms-runtime-lib=static",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-Xclang",
        "-cfguard",
        "-o",
        out,
        SRC,
        "-Wl,/WX,/guard:cf,/DEPENDENTLOADFLAG:0x800,/CETCOMPAT",
      }
    end,
  },
}

local LOAD_ERRORS = {
  [0xC0000135] = "a DLL it imports is missing",
  [0xC0000139] = "a function it imports is missing",
  [0xC000007B] = "it is built for another machine",
  [0xC0000005] = "it crashed",
}

local BUILD_ENV = { CL = "", _CL_ = "", LINK = "", _LINK_ = "" }

local exe_path, failure
local checked_at = 0
local building = false
local waiting = {}
local stamped = {}

local function stamp()
  local st = uv.fs_stat(SRC)

  if not st or st.type ~= "file" then
    return nil
  end

  if stamped.sec == st.mtime.sec and stamped.nsec == st.mtime.nsec and stamped.size == st.size then
    return stamped.value
  end

  if vim.in_fast_event() then
    return stamped.value
  end

  local f = io.open(SRC, "rb")
  local text = f and f:read("*a")

  if f then
    f:close()
  end

  if not text then
    return nil
  end

  local how = {}

  for _, c in ipairs(COMPILERS) do
    how[#how + 1] = table.concat(c.args("OUT", c.name), " ")
  end

  local value = ("%s-%x"):format(vim.fn.sha256(text .. "\0" .. table.concat(how, "\n")):sub(1, 16), #text)

  stamped = { sec = st.mtime.sec, nsec = st.mtime.nsec, size = st.size, value = value }

  return value
end

local function retry_key()
  local parts = {}

  for _, c in ipairs(COMPILERS) do
    parts[#parts + 1] = c.locate() or ""
  end

  for _, name in ipairs({ "INCLUDE", "LIB", "VCToolsInstallDir" }) do
    parts[#parts + 1] = uv.os_getenv(name) or ""
  end

  return vim.fn.sha256(table.concat(parts, "\n")):sub(1, 16)
end

local function exe_for(s)
  return vim.fs.joinpath(DIR, "windows_wsl_bridge-" .. s .. ".exe")
end

local function log_for(s)
  return vim.fs.joinpath(DIR, "windows_wsl_bridge-" .. s .. ".log")
end

local function valid_exe(path)
  if type(path) ~= "string" or vim.fs.dirname(vim.fs.normalize(path)):lower() ~= DIR:lower() then
    return false
  end

  local st = uv.fs_stat(path)

  return st ~= nil and st.type == "file" and st.size > 0 and vim.fs.basename(path):match(EXE_NAME) ~= nil
end

local function newest_build(except)
  local best, best_time

  for name in vim.fs.dir(DIR) do
    local path = vim.fs.joinpath(DIR, name)

    if path ~= except and valid_exe(path) then
      local st = uv.fs_stat(path)

      if st and (not best_time or st.mtime.sec > best_time) then
        best, best_time = path, st.mtime.sec
      end
    end
  end

  return best
end

local function describe(res)
  local code = type(res) == "table" and tonumber(res.code) or -1

  if code == 124 then
    return "timed out"
  end

  return ("exit %d (0x%08X)%s"):format(code, code % 0x100000000, LOAD_ERRORS[code] and ": " .. LOAD_ERRORS[code] or "")
end

local reports = {}
local reported = {}

function M.report(message, level)
  if type(message) ~= "string" or message == "" then
    return
  end

  message = message:sub(1, 500)
  reports[#reports + 1] = os.date("%H:%M:%S ") .. message
  if #reports > 20 then
    table.remove(reports, 1)
  end

  if not reported[message] then
    reported[message] = true
    vim.schedule(function()
      vim.notify(message, level or vim.log.levels.WARN, { title = "windows_wsl_bridge" })
    end)
  end
end

function M.reports()
  return vim.deepcopy(reports)
end

local function prune(keep)
  for name in vim.fs.dir(DIR) do
    local path = vim.fs.joinpath(DIR, name)
    local owner = tonumber(name:match("^windows_wsl_bridge%-%x+%-%x+%.(%d+)%.tmp%.%a+$"))

    if (name:match(EXE_NAME) and path ~= keep) or name == "windows_wsl_bridge.obj" then
      os.remove(path)
    elseif owner and owner ~= vim.fn.getpid() and uv.kill(owner, 0) ~= 0 then
      os.remove(path)
    end
  end
end

local function finish(exe, why)
  exe_path, failure, building = exe or false, why, false
  checked_at = uv.now()

  if not exe and why then
    M.report("windows_wsl_bridge: " .. why, vim.log.levels.ERROR)
  end

  local callbacks = waiting

  waiting = {}
  for _, fn in ipairs(callbacks) do
    pcall(fn, exe or nil, why)
  end
end

local function compile(s)
  local found = {}

  for _, c in ipairs(COMPILERS) do
    local program = c.locate()

    if program then
      found[#found + 1] = { compiler = c, program = program }
    end
  end

  if #found == 0 then
    return finish(nil, "no Visual Studio cl (its MSVC environment), nor clang targeting MSVC on PATH")
  end

  vim.fn.mkdir(DIR, "p")

  local exe, log = exe_for(s), log_for(s)
  local tmp = ("%s.%d.tmp.exe"):format(exe:sub(1, -5), vim.fn.getpid())
  local object = tmp:sub(1, -5) .. ".obj"
  local transcript = {}

  local function try(i)
    local c = found[i] and found[i].compiler

    if not c then
      os.remove(tmp)
      pcall(vim.fn.writefile, vim.list_extend({ ("retry %s %d"):format(retry_key(), os.time()) }, transcript), log)

      local why = "no compiler built it; " .. log .. " has their output"
      local older = newest_build(exe)

      return finish(older, why)
    end

    local cmd = c.args(tmp, found[i].program)

    local function failed(why, res)
      vim.list_extend(transcript, { "$ " .. table.concat(cmd, " "), why })
      vim.list_extend(transcript, vim.split(((res and res.stdout) or "") .. ((res and res.stderr) or ""), "\n"))
      os.remove(tmp)
      os.remove(object)

      return try(i + 1)
    end

    local options = { cwd = DIR, text = true, timeout = BUILD_TIMEOUT_MS, env = BUILD_ENV }

    local ok = pcall(vim.system, cmd, options, function(res)
      vim.schedule(function()
        os.remove(object)

        if res.code ~= 0 or not uv.fs_stat(tmp) then
          return failed("build failed: " .. describe(res), res)
        end

        local want = ("windows_wsl_bridge %s x64\n"):format(c.version)
        local started = pcall(
          vim.system,
          { tmp, "version" },
          { text = true, timeout = SELFTEST_TIMEOUT_MS },
          function(t)
            vim.schedule(function()
              if t.code ~= 0 or t.stdout ~= want then
                return failed(("self-test failed: %s, answered %q"):format(describe(t), t.stdout or ""), t)
              end

              if not uv.fs_rename(tmp, exe) then
                os.remove(tmp)
              end

              if not valid_exe(exe) then
                return finish(nil, "could not write " .. exe)
              end

              prune(exe)
              finish(exe)
            end)
          end
        )

        if not started then
          failed("self-test could not start", nil)
        end
      end)
    end)

    if not ok then
      failed("could not start " .. c.name, nil)
    end
  end

  try(1)
end

---@param opts? { build?: boolean }
function M.path(opts)
  if not WIN then
    return nil, "Windows only"
  end

  if exe_path then
    if uv.now() - checked_at < RECHECK_MS then
      return exe_path
    end

    checked_at = uv.now()
    if valid_exe(exe_path) then
      return exe_path
    end

    exe_path = nil
  end

  if exe_path == false and not building then
    return nil, failure
  end

  if building then
    return nil, "building"
  end

  local s = stamp()

  if not s then
    if vim.in_fast_event() then
      return nil, "not looked for yet"
    end

    exe_path, failure = false, "native/windows_wsl_bridge.c is missing"

    return nil, failure
  end

  local exe = exe_for(s)

  if valid_exe(exe) then
    exe_path, checked_at = exe, uv.now()

    return exe
  end

  local log = log_for(s)

  if uv.fs_stat(log) then
    if vim.in_fast_event() then
      return nil, "not looked for yet"
    end

    local f = io.open(log, "rb")
    local first = f and f:read("*l") or ""

    if f then
      f:close()
    end

    local key, when = first:match("^retry (%x+) (%d+)$")

    if key ~= retry_key() or os.time() - (tonumber(when) or 0) > RETRY_AFTER_S then
      os.remove(log)
    else
      local older = newest_build(exe)

      failure = "the build of the current source failed; " .. log .. " has the compiler output"
      if older then
        exe_path, checked_at = older, uv.now()

        return older
      end

      exe_path = false

      return nil, failure
    end
  end

  if opts and opts.build == false then
    return nil, "not built yet"
  end

  building = true
  vim.schedule(function()
    compile(s)
  end)

  return nil, "building"
end

function M.is_building()
  return building
end

function M.on_ready(fn)
  local exe, why = M.path()

  if exe then
    fn(exe)
  elseif building then
    waiting[#waiting + 1] = fn
  else
    fn(nil, why)
  end
end

-- CLI callers (scripts/wsl.lua): waits for the on-demand build if not compiled yet.
function M.ensure_sync()
  local exe, why = M.path()

  if exe then
    return exe
  end

  if not building then
    return nil, why
  end

  vim.wait(BUILD_TIMEOUT_MS + SELFTEST_TIMEOUT_MS + 2000, function()
    return not building
  end, 50)

  return M.path({ build = false })
end

M._valid_exe = valid_exe
M._describe = describe
M._stamp = stamp
M._retry_key = retry_key
M._exe_for = exe_for
M._log_for = log_for

return M
