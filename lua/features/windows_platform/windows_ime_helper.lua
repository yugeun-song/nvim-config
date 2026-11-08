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

local DIR = vim.fs.normalize(require("features.maintenance.local_storage").path("data", "windows_ime_helper"))
local EXE_NAME = "^windows_ime_helper%-%x+%-%x+%.exe$"
local BUILD_TIMEOUT_MS = 120000
local SELFTEST_TIMEOUT_MS = 5000
local RECHECK_MS = 2000

-- cl first, as the source is written for it. Warnings fail the build (/WX, -Werror), the linker's too: a library
-- for another machine is only a warning otherwise. The C runtime is linked in, so the program loads no DLL but
-- the system's own.
local COMPILERS = {
  {
    name = "cl",
    version = "msvc",
    args = function(out)
      return {
        "cl",
        "/nologo",
        -- The object beside the build's own temporary .exe: another Neovim may be building at the same time.
        "/Fo"
          .. out:sub(1, -5)
          .. ".obj",
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
    args = function(out)
      return {
        "clang",
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

local exe_path, failure
local checked_at = 0
local building = false
local waiting = {}

local function stamp()
  local st = uv.fs_stat(SRC)

  return st and st.type == "file" and ("%x-%x"):format(st.mtime.sec, st.size)
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
    ("Built the Windows helper with %s: the IME switch is on; the 한/EN and CAPS indicators start with the next Neovim."):format(
      compiler
    ),
    vim.log.levels.INFO
  )
end

local function compile(s)
  local found = vim.tbl_filter(function(c)
    return vim.fn.executable(c.name) == 1
  end, COMPILERS)

  if #found == 0 then
    return finish(nil, "no Visual Studio cl, nor clang targeting MSVC, on PATH; the features that need it are off")
  end

  vim.fn.mkdir(DIR, "p")

  local exe, log = exe_for(s), log_for(s)
  local tmp = ("%s.%d.tmp.exe"):format(exe:sub(1, -5), vim.fn.getpid())
  local object = tmp:sub(1, -5) .. ".obj"
  local transcript = {}

  local function try(i)
    local c = found[i]

    if not c then
      os.remove(tmp)
      pcall(vim.fn.writefile, transcript, log)

      return finish(nil, "no compiler built it; " .. log .. " has their output, delete it to retry")
    end

    local cmd = c.args(tmp)

    local function failed(why, res)
      vim.list_extend(transcript, { "$ " .. table.concat(cmd, " "), why })
      vim.list_extend(transcript, vim.split(((res and res.stdout) or "") .. ((res and res.stderr) or ""), "\n"))
      os.remove(tmp)
      os.remove(object)

      return try(i + 1)
    end

    local ok = pcall(vim.system, cmd, { cwd = DIR, text = true, timeout = BUILD_TIMEOUT_MS }, function(res)
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
                require("features.external_programs.registered_programs").refresh_shims(exe)
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
    exe_path, failure = false, "native/windows_ime_helper.c is missing"

    return nil, failure
  end

  local exe = exe_for(s)

  if valid_exe(exe) then
    exe_path, checked_at = exe, uv.now()

    return exe
  end

  if uv.fs_stat(log_for(s)) then
    exe_path, failure = false, "build failed; " .. log_for(s) .. " has the compiler output, delete it to retry"

    return nil, failure
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

  pending = (pending or "") .. (data or "")
  if #pending > 64 then
    return lines, "", "watch-input-state: output without line ends"
  end

  while true do
    local line, rest = pending:match("^([^\n]*)\n(.*)$")

    if not line then
      return lines, pending, nil
    end

    pending = rest
    if not line:match("^[01][01]$") then
      return lines, "", "watch-input-state: unexpected output"
    end

    lines[#lines + 1] = line
  end
end

M._accept_output = accept_output
M._valid_exe = valid_exe
M._describe = describe

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
    stderr = true,
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
      end
    end,
  }, function(res)
    pending = ""
    watcher = nil

    -- 0 is Neovim closing it, 15 this side stopping it; anything else is the watcher failing.
    if res.code ~= 0 and res.signal ~= 15 and not watch_failure then
      watch_failure = "watch-input-state: " .. describe(res)
      M.report_exit("watch-input-state", res)
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
