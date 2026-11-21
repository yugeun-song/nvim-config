-- Windows only: native/windows_ime_helper.c, the native helper behind the IME switch, the 한/EN and CAPS indicators, the
-- window raise and the tool shims. Built in the background into stdpath("data")/nvim-config/windows_ime_helper, once
-- per version of the source, by Visual Studio's cl or clang targeting MSVC (the source refuses anything else); nothing
-- is downloaded. Nothing it hands back is trusted unchecked: a build that warns, links oddly or cannot load its imports
-- is discarded (it must answer `version` exactly), the program is re-checked before use, and a watcher that says
-- anything but its two digits is stopped. It runs only as Neovim's child and ends with it
-- (native/windows_ime_helper.c).
local M = {}

local uv = vim.uv

-- Every caller is behind has("win32") already; this keeps a stray one from ever compiling anything elsewhere.
local WIN = vim.fn.has("win32") == 1

-- The repository is what comes before this file's lua/ directory, at whatever depth the module sits.
local SRC = vim.fs.joinpath(
  vim.fs.normalize(debug.getinfo(1, "S").source:sub(2)):match("^(.*)/lua/") or vim.fn.stdpath("config"),
  "native",
  "windows_ime_helper.c"
)

local DIR = vim.fs.normalize(require("features.util.storage").path("data", "windows_ime_helper"))
local EXE_NAME = "^windows_ime_helper%-%x+%-%x+%.exe$"
local BUILD_TIMEOUT_MS = 120000
local COMPILER_WAIT_MS = 20000
local SELFTEST_TIMEOUT_MS = 5000
local RECHECK_MS = 2000

-- The cl of the toolset the MSVC environment names (Neovim's, from a Developer prompt or the captured one in
-- lua/features/lang/c/msvc_toolchain/developer_environment.lua), by its full path: PATH can list folders other
-- users may write before the toolset's own.
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

-- cl first, as the source is written for it. Warnings fail the build (/WX, -Werror), the linker's too: a library
-- for another machine is only a warning otherwise. The C runtime is linked in, so the program loads no DLL but
-- the system's own.
local COMPILERS = {
  {
    name = "cl",
    version = "msvc",
    locate = cl_in_toolset,
    args = function(out, program)
      return {
        program,
        "/nologo",
        -- The object beside the build's own temporary .exe: another Neovim may be building at the same time.
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
        -- What cl gets from /guard:cf (clang-cl passes the same).
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

-- What a failed self-test's exit status means, for the log.
local LOAD_ERRORS = {
  [0xC0000135] = "a DLL it imports is missing",
  [0xC0000139] = "a function it imports is missing",
  [0xC000007B] = "it is built for another machine",
  [0xC0000005] = "it crashed",
}

-- What the build takes from the environment but its own arguments: cl's and link's extra options.
local BUILD_ENV = { CL = "", _CL_ = "", LINK = "", _LINK_ = "" }

-- A failed build is tried again once a day, or at once when something it depends on changed (retry_key).
local RETRY_AFTER_S = 24 * 3600

local exe_path, failure
local checked_at = 0
local building = false
local waiting = {}
local stamped = {}

-- A build's name: a hash of the source and of how each compiler is run, and the source's size, so a changed flag
-- builds anew as a changed source does. Hashed again only when the source's time or size moves; nil in a libuv
-- callback before the first hash.
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

-- What could make a failed build pass now: the compilers there are, and the headers and libraries they read. Not
-- PATH: Mason puts its bin in front of it once it loads, so a failure recorded after that never matched the next start.
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
  return vim.fs.joinpath(DIR, "windows_ime_helper-" .. s .. ".exe")
end

local function log_for(s)
  return vim.fs.joinpath(DIR, "windows_ime_helper-" .. s .. ".log")
end

-- Ours: a non-empty file named as a build, in DIR itself.
local function valid_exe(path)
  if type(path) ~= "string" or vim.fs.dirname(vim.fs.normalize(path)):lower() ~= DIR:lower() then
    return false
  end

  local st = uv.fs_stat(path)

  return st ~= nil and st.type == "file" and st.size > 0 and vim.fs.basename(path):match(EXE_NAME) ~= nil
end

-- The newest build in DIR but except: what ran before a newer source failed to build (prune() removes older
-- builds only after one succeeds).
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

local function finish(exe, why)
  exe_path, failure, building = exe or false, why, false
  checked_at = uv.now()

  if not exe and why then
    M.report("windows_ime_helper: " .. why, vim.log.levels.ERROR)
  end

  local callbacks = waiting

  waiting = {}
  if exe then
    for _, fn in ipairs(callbacks) do
      pcall(fn, exe)
    end
  end
end

-- Builds of an older source, unless a running watcher or shim still holds one open, and what a build left
-- when its Neovim quit while the compiler ran: a temporary .exe or cl object whose process is gone.
local function prune(keep)
  for name in vim.fs.dir(DIR) do
    local path = vim.fs.joinpath(DIR, name)
    local owner = tonumber(name:match("^windows_ime_helper%-%x+%-%x+%.(%d+)%.tmp%.%a+$"))

    -- winctl-* and winctl.obj: what the helper's builds were named before it was windows_ime_helper.
    if (name:match(EXE_NAME) and path ~= keep) or name == "windows_ime_helper.obj" or name:match("^winctl[%-.]") then
      os.remove(path)
    elseif owner and owner ~= vim.fn.getpid() and uv.kill(owner, 0) ~= 0 then
      os.remove(path)
    end
  end
end

local function describe(res)
  local code = type(res) == "table" and tonumber(res.code) or -1

  if code == 124 then
    return "timed out"
  end

  return ("exit %d (0x%08X)%s"):format(code, code % 0x100000000, LOAD_ERRORS[code] and ": " .. LOAD_ERRORS[code] or "")
end

-- Not while Neovim still starts: before the notifier loads this would stop at "Press ENTER". Safe from libuv
-- callbacks too.
local function notify_later(message, level)
  local function show()
    vim.notify(message, level, { title = "windows_ime_helper" })
  end

  vim.schedule(function()
    if vim.g.did_very_lazy then
      return show()
    end

    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      once = true,
      callback = function()
        vim.schedule(show)
      end,
    })
  end)
end

local reports = {}
local reported = {}

-- A failure reaches Neovim: each distinct message is shown once a session, and the last 20 stay for
-- :checkhealth.
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
    notify_later(message, level or vim.log.levels.WARN)
  end
end

-- A windows_ime_helper run that did not end in 0, with what it said on stderr.
function M.report_exit(what, res)
  local said = type(res) == "table" and type(res.stderr) == "string" and vim.trim(res.stderr):match("[^\r\n]+") or nil

  M.report(("windows_ime_helper %s: %s%s"):format(tostring(what), describe(res), said and (": " .. said) or ""))
end

function M.reports()
  return vim.deepcopy(reports)
end

local function announce(compiler)
  notify_later(
    ("Built the Windows helper with %s: the IME switch and the 한/EN and CAPS indicators are on."):format(compiler),
    vim.log.levels.INFO
  )
end

local function compile(s, is_second_try)
  local found = {}

  for _, c in ipairs(COMPILERS) do
    local program = c.locate()

    if program then
      found[#found + 1] = { compiler = c, program = program }
    end
  end

  if #found == 0 then
    -- cl comes with the MSVC environment, which a first start, or one after a Visual Studio update, captures in
    -- the background a few seconds in: asked once more when it has had the time.
    if not is_second_try and (uv.os_getenv("VCToolsInstallDir") or "") == "" then
      return vim.defer_fn(function()
        compile(s, true)
      end, COMPILER_WAIT_MS)
    end

    return finish(
      nil,
      "no Visual Studio cl (its MSVC environment), nor clang targeting MSVC on PATH; the features that need it are off"
    )
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
      -- The first line: what to compare with later, and when.
      pcall(vim.fn.writefile, vim.list_extend({ ("retry %s %d"):format(retry_key(), os.time()) }, transcript), log)

      local why = "no compiler built it; " .. log .. " has their output"
      local older = newest_build(exe)

      if older then
        M.report("windows_ime_helper: " .. why .. "; the previous build runs meanwhile", vim.log.levels.ERROR)
      end

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

        -- The program must load and answer exactly: an import that fails, a wrong machine or a wrong compiler
        -- shows here, not later in front of the user.
        local want = ("windows_ime_helper %s x64\n"):format(c.version)
        local started = pcall(
          vim.system,
          { tmp, "version" },
          { text = true, timeout = SELFTEST_TIMEOUT_MS },
          function(t)
            vim.schedule(function()
              if t.code ~= 0 or t.stdout ~= want then
                return failed(("self-test failed: %s, answered %q"):format(describe(t), t.stdout or ""), t)
              end

              -- Another Neovim may have built the same version meanwhile; either copy is the same program.
              if not uv.fs_rename(tmp, exe) then
                os.remove(tmp)
              end

              if not valid_exe(exe) then
                return finish(nil, "could not write " .. exe)
              end

              prune(exe)
              pcall(function()
                require("features.util.tool_paths").refresh_shims(exe)
              end)

              finish(exe)
              announce(c.name)
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

-- The helper, or nil and why not. A missing build starts in the background unless opts.build is false, and
-- on_ready runs once it lands. A build deleted while Neovim runs is noticed within RECHECK_MS and built again.
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

    exe_path, failure = false, "native/windows_ime_helper.c is missing"

    return nil, failure
  end

  local exe = exe_for(s)

  if valid_exe(exe) then
    exe_path, checked_at = exe, uv.now()

    return exe
  end

  local log = log_for(s)

  if uv.fs_stat(log) then
    local f = io.open(log, "rb")
    local first = f and f:read("*l") or ""

    if f then
      f:close()
    end

    local key, when = first:match("^retry (%x+) (%d+)$")

    -- Something the build depends on changed, or a day passed: it is tried again below.
    if not vim.in_fast_event() and (key ~= retry_key() or os.time() - (tonumber(when) or 0) > RETRY_AFTER_S) then
      os.remove(log)
    else
      local older = newest_build(exe)

      failure = "the build of the current source failed; " .. log .. " has the compiler output"
      M.report(
        "windows_ime_helper: " .. failure .. (older and "; the previous build runs meanwhile" or ""),
        vim.log.levels.ERROR
      )

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

local watcher
local watch_failure

-- Splits what the watcher wrote into its "<caps><ime>" lines: the lines, what is left of an unfinished one, and
-- why the output is refused, if it is (anything but two binary digits, or a line that never ends).
local function accept_output(pending, data)
  local lines = {}
  local text = (pending or "") .. (data or "")
  local start = 1

  -- Every whole line first: Neovim may read a burst of them at once, after a while busy.
  while true do
    local stop = text:find("\n", start, true)

    if not stop then
      break
    end

    local line = text:sub(start, stop - 1)

    if not line:match("^[01][01]$") then
      return lines, "", "watch-input-state: unexpected output"
    end

    lines[#lines + 1] = line
    start = stop + 1
  end

  local rest = text:sub(start)

  -- Only what follows the last line end is unfinished, and a line is three bytes.
  if #rest > 64 then
    return lines, "", "watch-input-state: output without line ends"
  end

  return lines, rest, nil
end

M._accept_output = accept_output
M._valid_exe = valid_exe
M._describe = describe
M._stamp = stamp
M._retry_key = retry_key
M._exe_for = exe_for
M._log_for = log_for

-- The one long-lived `windows_ime_helper watch-input-state`: on_data gets each "<caps><ime>" line. Reused while it
-- runs. Anything else on its stdout means the two sides disagree, and the watcher is stopped rather than believed.
function M.watch(on_data)
  local exe = M.path()

  if not exe then
    return nil
  end

  if watcher and not watcher:is_closing() then
    return watcher
  end

  local pending = ""
  local said, said_pending = "", ""
  local proc

  local function reject(why)
    watch_failure = why
    pending = ""
    M.report("windows_ime_helper " .. why)

    if proc and not proc:is_closing() then
      pcall(proc.kill, proc, 15)
    end
  end

  local is_spawned, started = pcall(vim.system, { exe, "watch-input-state", tostring(vim.fn.getpid()) }, {
    stdin = true,
    -- Kept for the report when it ends; an IME that did not switch is said at once, and the watcher goes on.
    stderr = function(_, data)
      if not data then
        return
      end

      said = (said .. data):sub(-4096)
      said_pending = said_pending .. data

      while true do
        local line, rest = said_pending:match("^([^\n]*)\n(.*)$")

        if not line then
          break
        end

        said_pending = rest
        if line:find("did not take the mode", 1, true) then
          M.report("windows_ime_helper " .. vim.trim(line))
        end
      end

      said_pending = said_pending:sub(-1024)
    end,
    text = true,
    stdout = function(_, data)
      if not data then
        return
      end

      local lines, rest, why = accept_output(pending, data)

      pending = rest
      for _, line in ipairs(lines) do
        on_data(line)
      end

      if why then
        reject(why)
      elseif #lines > 0 then
        -- A watcher that reports again: what stopped an earlier one is over (:checkhealth reads this).
        watch_failure = nil
      end
    end,
  }, function(res)
    pending = ""
    watcher = nil

    -- 0 is Neovim closing it, 15 this side stopping it; anything else is the watcher failing.
    if res.code ~= 0 and res.signal ~= 15 and not watch_failure then
      watch_failure = "watch-input-state: " .. describe(res)
      M.report_exit("watch-input-state", vim.tbl_extend("force", res, { stderr = said }))
    end
  end)

  if not is_spawned then
    M.report("windows_ime_helper watch-input-state: could not start: " .. tostring(started))
  end

  proc = is_spawned and started or nil
  watcher = proc

  return watcher
end

-- A command to the running watcher: e (IME to English), p (pause), r (resume). False when none runs, or for
-- anything else: the watcher would stop on it.
function M.send(cmd)
  if (cmd ~= "e" and cmd ~= "p" and cmd ~= "r") or not watcher or watcher:is_closing() then
    return false
  end

  return (pcall(watcher.write, watcher, cmd))
end

-- Whether a build runs, or waits for its compiler: M.on_ready hears of its success.
function M.is_building()
  return building
end

-- fn(exe) now when the helper is there, else after the background build succeeds.
function M.on_ready(fn)
  local exe = M.path()

  if exe then
    fn(exe)
  elseif building then
    waiting[#waiting + 1] = fn
  end
end

-- For :checkhealth: why a watcher stopped, if one did.
function M.watch_failure()
  return watch_failure
end

return M
