local M = {}

local TITLE = "Debug"

local reported = {}
local pending = {}
local running = {}

local SILENT_STOP = {
  breakpoint = true,
  step = true,
  pause = true,
  entry = true,
  attach = true,
  launch = true,
  ["goto"] = true,
  ["function breakpoint"] = true,
  ["data breakpoint"] = true,
  ["instruction breakpoint"] = true,
}

local function emit(level, msg, timeout)
  vim.notify(msg, level, { title = TITLE, timeout = timeout })
end

-- Everything the debugger says, kept so a message that scrolled past can still
-- be read.  noice swallows notifications into its own history and gdb's own
-- output goes to the adapter log, so without this there is no one place to look.
M.history = {}
local HISTORY_MAX = 400

local function record(level, msg)
  M.history[#M.history + 1] = {
    at = os.date("%H:%M:%S"),
    level = level,
    text = tostring(msg):gsub("\n", " "),
  }
  if #M.history > HISTORY_MAX then
    table.remove(M.history, 1)
  end
end

function M.info(msg)
  record("INFO", msg)
  emit(vim.log.levels.INFO, msg, 2500)
end

function M.warn(msg)
  record("WARN", msg)
  emit(vim.log.levels.WARN, msg, 5000)
end

function M.error(msg)
  record("ERROR", msg)
  emit(vim.log.levels.ERROR, msg, 7000)
end

local function base(path)
  return path and path ~= "" and vim.fs.basename(path) or nil
end

local function debug_info(path)
  local ok, discover = pcall(require, "dbg.discover")
  if not ok then
    return nil
  end
  return discover.elf_debug_info(path)
end

local function on_initialized(session)
  local cfg = session.config or {}
  if cfg.request == "attach" then
    local where = cfg.target or (cfg.pid and ("pid " .. cfg.pid)) or base(cfg.program) or "target"
    M.info("Attached to " .. where)
  else
    local prog = base(cfg.program) or "program"
    -- Spell out "no arguments": <leader>dc replays the last configuration, so a
    -- program that needs argv keeps starting without it and exits before any
    -- breakpoint is reached.
    local args = (type(cfg.args) == "table" and #cfg.args > 0) and (" " .. table.concat(cfg.args, " "))
      or "  (no arguments)"
    M.info("Running " .. prog .. args)
  end
  if cfg.program and debug_info(cfg.program) == "none" then
    M.warn(
      (base(cfg.program) or "the program")
        .. " carries no debug info, so no breakpoint can bind and there is no source stepping. Rebuild with -g."
    )
  end
end

-- An unverified breakpoint is normal before the program is loaded: gdb answers
-- "pending" and binds it once the symbols arrive.  Only the ones still unbound
-- when the target is live, or at session end, are worth a word.
local function why_unbound(session)
  local prog = (session.config or {}).program
  local state = prog and debug_info(prog)
  if state == "none" then
    return (base(prog) or "the program") .. " was built without -g"
  end
  if state == "external" then
    return "the debug info sits in a separate file gdb could not locate"
  end
  if (session.config or {}).request == "attach" then
    return "the loaded symbols do not cover this source"
  end
  return "the running binary does not match this source"
end

local function report_pending(session)
  local bucket = pending[session.id]
  pending[session.id] = nil
  if not bucket or vim.tbl_isempty(bucket) then
    return
  end
  local by_source = {}
  for _, rec in pairs(bucket) do
    local name = base(rec.path) or "source"
    by_source[name] = by_source[name] or {}
    table.insert(by_source[name], rec.line or 0)
  end
  local why = why_unbound(session)
  for name, lines in pairs(by_source) do
    table.sort(lines)
    M.warn(("%s: line %s never bound — %s"):format(name, table.concat(lines, ","), why))
  end
end

local function on_set_breakpoints(session, err, response, payload)
  if err or type(response) ~= "table" or type(response.breakpoints) ~= "table" then
    return
  end
  local path = ((payload or {}).source or {}).path
  local asked = (payload or {}).breakpoints or {}
  local bucket = pending[session.id] or {}
  pending[session.id] = bucket
  for id, rec in pairs(bucket) do
    if rec.path == path then
      bucket[id] = nil
    end
  end
  for i, bp in ipairs(response.breakpoints) do
    if bp.verified == false then
      bucket[bp.id or ("slot" .. i)] = { path = path, line = bp.line or (asked[i] or {}).line or 0 }
    end
  end
  if running[session.id] then
    report_pending(session)
  end
end

local function on_breakpoint_event(session, body)
  local bp = body and body.breakpoint
  local bucket = bp and bp.id and pending[session.id]
  if not bucket then
    return
  end
  if bp.verified then
    bucket[bp.id] = nil
  elseif bucket[bp.id] and bp.line then
    bucket[bp.id].line = bp.line
  end
end

local function on_stopped(session, body)
  running[session.id] = true
  local reason = body and body.reason
  if not reason or SILENT_STOP[reason] then
    return
  end
  local text = body.description or body.text
  M.warn("Stopped: " .. reason .. (text and (" — " .. text) or ""))
end

local function on_exited(session, body)
  reported[session.id] = true
  report_pending(session)
  local code = body and body.exitCode
  if code and code ~= 0 then
    M.warn(("Program exited with code %s"):format(code))
  else
    M.info("Program exited normally")
  end
end

local function forget(session)
  reported[session.id] = nil
  pending[session.id] = nil
  running[session.id] = nil
end

local function on_terminated(session)
  report_pending(session)
  if not reported[session.id] then
    M.info("Debug session ended")
  end
  forget(session)
end

local function on_disconnect(session)
  report_pending(session)
  if not reported[session.id] then
    if (session.config or {}).request == "attach" then
      M.info("Detached; the target keeps running")
    else
      M.info("Debug session ended")
    end
  end
  forget(session)
end

function M.setup(dap)
  -- These messages are written for gdb/kernel sessions; a managed adapter keeps
  -- nvim-dap's own reporting.
  local function gated(fn)
    return function(session, ...)
      if not require("dbg.context").is_low_level(session) then
        return
      end
      return fn(session, ...)
    end
  end
  dap.listeners.after.event_initialized["dbg_notify"] = gated(on_initialized)
  dap.listeners.after.setBreakpoints["dbg_notify"] = gated(on_set_breakpoints)
  dap.listeners.after.event_breakpoint["dbg_notify"] = gated(on_breakpoint_event)
  dap.listeners.after.event_stopped["dbg_notify"] = gated(on_stopped)
  dap.listeners.after.event_exited["dbg_notify"] = gated(on_exited)
  dap.listeners.after.event_terminated["dbg_notify"] = gated(on_terminated)
  dap.listeners.after.disconnect["dbg_notify"] = gated(on_disconnect)
end

-- One place to look after something scrolled past: what the debugger said, then
-- the adapter's own log, which is where a gdb-side failure lands.
function M.show_log()
  local lines = { "  Debugger messages (newest last)", "" }
  if #M.history == 0 then
    lines[#lines + 1] = "  nothing recorded this session"
  end
  for _, e in ipairs(M.history) do
    lines[#lines + 1] = ("  %s  %-5s %s"):format(e.at, e.level, e.text)
  end
  local log = vim.fn.stdpath("state") .. "/dap.log"
  local fd = io.open(log, "r")
  if fd then
    local all = {}
    for line in fd:lines() do
      all[#all + 1] = line
    end
    fd:close()
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  " .. log .. " (last 60 lines)"
    lines[#lines + 1] = ""
    for i = math.max(1, #all - 59), #all do
      lines[#lines + 1] = "  " .. all[i]
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local width = math.min(vim.o.columns - 4, 140)
  local height = math.min(vim.o.lines - 6, math.max(#lines, 5))
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Debugger log ",
  })
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
  vim.api.nvim_win_set_cursor(0, { #lines, 0 })
end

return M
