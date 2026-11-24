-- The terminal file managers Open Folder runs (<leader>fo, `o` on the dashboard; lua/features/editor/open_folder.lua).
--
-- PRIORITY ranks them: Open Folder runs the first one that is on PATH (or registered with :ToolPath) and passes its
-- usability check (probe), passing over missing or broken ones. When none is installed and runnable, Open Folder is
-- disabled (neither `<leader>fo` nor the dashboard `o` entry is registered). Each Open Folder looks again, so one that
-- disappears or stops working while Neovim runs gives way to the next, or disables Open Folder if none remains.
--
-- To add one (nnn, lf, ranger, ...), give ADAPTERS an entry and put its name in PRIORITY at its rank. An entry has:
--   executable       the program, looked up on PATH
--   url              its home page, named by :checkhealth when nothing is installed
--   probe(exe)       (optional) checks that exe can run and supports the flags command() uses, returning ok, why?.
--                    Cached per resolved path and file stat; returning false skips this entry for the next one.
--   command(start, out) -> argv, env?
--                    argv opens the program at the folder start, as a list that no shell parses. out.cwd_file and
--                    out.chooser_file are temporary paths it may write: the folder it quits in, and the files
--                    opened in it, one per line. env (optional) adds variables, for a program that takes such a
--                    path from its environment.
--   capture_stdout   (optional) true for a program that prints the folder it quits in instead of writing a file
--   read(got) -> dir?, chosen, err?
--                    what the program left: got.cwd_file and got.chooser_file hold the lines of those files, and
--                    got.stdout what it printed after leaving its alternate screen (escape sequences removed), when
--                    capture_stdout is set. dir is the folder it quit in (nil: none), chosen the paths opened in it,
--                    err why the output could not be read.
-- Then add the program to M.KNOWN in lua/features/util/tool_paths/init.lua, to PROGRAMS in scripts/update_credits.lua,
-- and to docs/features/editor.md, docs/dependencies.md and docs/keymaps.md.
local M = {}

local TITLE = "Open Folder"
local PROBE_TIMEOUT_MS = 2000

M.PRIORITY = { "superfile", "yazi" }

local function non_empty(lines)
  return vim.tbl_filter(function(line)
    return line ~= ""
  end, lines)
end

local function run_probe(argv, env)
  local started, proc = pcall(vim.system, argv, { text = true, timeout = PROBE_TIMEOUT_MS, env = env })

  if not started then
    return false, "could not start: " .. tostring(proc)
  end

  local res = proc:wait()

  if res.code == 124 then
    return false, "timed out"
  elseif res.code ~= 0 then
    local detail = type(res.stderr) == "string" and vim.trim(res.stderr):match("[^\r\n]+") or nil

    return false, ("exited with code %d%s"):format(res.code, detail and (": " .. detail) or "")
  end

  return true, res.stdout or ""
end

M.ADAPTERS = {
  -- spf --print-last-dir prints the folder on every quit (q, Esc, Q); --chooser-file takes the file opened (Enter)
  -- and quits. Its TUI draws on stdout, so the folder is read from the terminal's output.
  superfile = {
    executable = "spf",
    url = "https://superfile.dev/",
    capture_stdout = true,
    probe = function(exe)
      -- spf writes default theme files on first invocation; keep the probe out of the user's XDG directories.
      local tmp = vim.fn.tempname()
      local ok, out = run_probe({ exe, "--help" }, {
        XDG_CONFIG_HOME = tmp,
        XDG_DATA_HOME = tmp,
        XDG_STATE_HOME = tmp,
        XDG_CACHE_HOME = tmp,
      })

      vim.fn.delete(tmp, "rf")
      if not ok then
        return false, out
      elseif not out:find("--print-last-dir", 1, true) or not out:find("--chooser-file", 1, true) then
        return false, "lacks --print-last-dir or --chooser-file"
      end

      return true
    end,
    command = function(start, out)
      return { "spf", "--print-last-dir", "--chooser-file", out.chooser_file, start }
    end,
    read = function(got)
      local chosen = non_empty(got.chooser_file)

      if got.stdout == nil then
        return nil, chosen, "never left its alternate screen, so the folder it quit in is unknown"
      end

      local lines = non_empty(vim.split(got.stdout, "\n", { plain = true }))

      if #lines > 1 then
        -- A folder name with a line break would print as two lines; neither is opened.
        return nil, chosen, ("printed %d lines where it prints one folder"):format(#lines)
      end

      return lines[1], chosen
    end,
  },
  -- q writes the folder to --cwd-file; Q quits without writing; Enter on a file writes --chooser-file and quits.
  yazi = {
    executable = "yazi",
    url = "https://yazi-rs.github.io/",
    probe = function(exe)
      -- yazi --help queries the terminal when attached to one and fails without a tty; --version works headless.
      local ok, out = run_probe({ exe, "--version" })

      if not ok then
        return false, out
      elseif not out:find("Yazi", 1, true) then
        return false, "unexpected --version output"
      end

      return true
    end,
    command = function(start, out)
      return { "yazi", "--cwd-file", out.cwd_file, "--chooser-file", out.chooser_file, start }
    end,
    read = function(got)
      return got.cwd_file[1], non_empty(got.chooser_file)
    end,
  },
}

local reports = {}

-- Shown as a notification, and the last 20 kept for :checkhealth features.editor.
function M.report(message, level)
  level = level or vim.log.levels.ERROR
  reports[#reports + 1] = os.date("%H:%M:%S ") .. message
  if #reports > 20 then
    table.remove(reports, 1)
  end

  vim.schedule(function()
    vim.notify(message, level, { title = TITLE })
  end)
end

function M.reports()
  return vim.deepcopy(reports)
end

local invalid_reported = {}

-- Why an entry cannot run, or nil when it can.
local function problem(name, adapter)
  if type(adapter) ~= "table" then
    return "is in PRIORITY but has no entry in ADAPTERS"
  elseif type(adapter.executable) ~= "string" or adapter.executable == "" then
    return "has no executable"
  elseif type(adapter.command) ~= "function" or type(adapter.read) ~= "function" then
    return "lacks command() or read()"
  elseif type(name) ~= "string" then
    return "has a name that is not a string"
  end
end

-- The entries in PRIORITY order, each with its name; a broken one is reported once a session and skipped.
function M.list()
  local list = {}

  for _, name in ipairs(M.PRIORITY) do
    local adapter = M.ADAPTERS[name]
    local why = problem(name, adapter)

    if why then
      if not invalid_reported[name] then
        invalid_reported[name] = true
        M.report(("file manager %s %s; it is skipped"):format(tostring(name), why))
      end
    else
      list[#list + 1] = vim.tbl_extend("keep", { name = name }, adapter)
    end
  end

  return list
end

local probe_cache = {}

-- Whether adapter's program is on PATH and runnable, with the reason when it is not; cached per resolved path and stat.
function M.probe(adapter)
  local exe = vim.fn.exepath(adapter.executable)

  if exe == "" then
    return false, "not on PATH"
  end

  local st = vim.uv.fs_stat(exe)
  local stamp = st and ("%s:%d:%d:%d"):format(exe, st.size, st.mtime.sec, st.mtime.nsec) or exe
  local cached = probe_cache[adapter.name]

  if cached and cached.stamp == stamp then
    return cached.ok, cached.why
  end

  local ok, why = true, nil

  if type(adapter.probe) == "function" then
    local ran, passed, reason = pcall(adapter.probe, exe)

    if not ran then
      ok, why = false, "probe failed: " .. tostring(passed)
    else
      ok, why = passed == true, reason
    end
  end

  probe_cache[adapter.name] = { stamp = stamp, ok = ok, why = why }

  return ok, why
end

-- The first installed and runnable entry in PRIORITY order, or nil.
function M.find()
  for _, adapter in ipairs(M.list()) do
    if M.probe(adapter) then
      return adapter
    end
  end
end

-- What the program printed after it left its alternate screen, without escape sequences or carriage returns; nil
-- when it never left one (it failed before drawing, say). Only the last leave counts: a program it ran meanwhile
-- (an editor) has its own.
function M.after_alternate_screen(raw)
  if type(raw) ~= "string" then
    return nil
  end

  local last
  local from = 1

  while true do
    local _, stop = raw:find("\27[?1049l", from, true)

    if not stop then
      break
    end

    last, from = stop, stop + 1
  end

  if not last then
    return nil
  end

  local text = raw:sub(last + 1)

  text = text:gsub("\27%][^\7\27]*\7", "") -- OSC ended by BEL
  text = text:gsub("\27%][^\7\27]*\27\\", "") -- OSC ended by ST
  text = text:gsub("\27%[[0-?]*[ -/]*[@-~]", "") -- CSI
  text = text:gsub("\27[ -~]", "") -- other two-byte escapes

  return (text:gsub("\r", ""))
end

return M
