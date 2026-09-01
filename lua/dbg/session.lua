local panel = require("dbg.panel")
local gdbq = require("dbg.gdbq")
local caps = require("dbg.caps")
local ui = require("dbg.ui")

local M = {}

local probes = {}
local caps_cache = nil

local ALWAYS = { "show architecture", "show endian" }

local BY_KIND = {
  kernel = { "lx-version", "kearly", "mmview" },
  userspace = { "checksec", "piebase", "info proc mappings" },
  bare = { "info files" },
}

function M.buffer()
  local buf, created = panel.buffer("session", "dbg-session")
  if created then
    vim.keymap.set("n", "r", function()
      M.probe()
    end, { buffer = buf, nowait = true, desc = "Target: refresh" })
  end
  return buf
end

function M.stop()
  local dap = require("dap")
  local session = dap.session()
  if not session then
    require("dbg.notify").info("No debug session is running")
    return
  end
  local cfg = session.config or {}
  if cfg.request == "attach" then
    dap.disconnect({ terminateDebuggee = false })
  else
    dap.terminate()
  end
end

-- The configuration nvim-dap actually ran, prompts already answered; replaying
-- it is what lets a second <leader>dc go straight to the breakpoints.
local last_config = nil

function M.remember(config)
  if type(config) ~= "table" then
    return
  end
  local copy = {}
  for k, v in pairs(config) do
    if type(k) ~= "string" or not k:match("^__") then
      copy[k] = v
    end
  end
  last_config = copy
end

function M.forget()
  last_config = nil
end

function M.last()
  return last_config
end

-- QEMU exposes every vCPU as a thread, so nvim-dap asks which of the halted
-- threads to move.  Answering with a CPU other than the one that reported the
-- stop resumes the whole machine, which is how a kernel runs away from its own
-- breakpoint.  Always move the thread the stop came from.
function M.focus(session)
  if not session then
    return nil
  end
  if session.stopped_thread_id then
    return session.stopped_thread_id
  end
  local remembered = session.dbg_stopped_thread
  local threads = session.threads or {}
  if remembered and threads[remembered] and threads[remembered].stopped then
    session.stopped_thread_id = remembered
    return remembered
  end
  for id, thread in pairs(threads) do
    if thread.stopped and thread.frames and #thread.frames > 0 then
      session.stopped_thread_id = id
      return id
    end
  end
  for id, thread in pairs(threads) do
    if thread.stopped then
      session.stopped_thread_id = id
      return id
    end
  end
  return nil
end

function M.cont()
  local dap = require("dap")
  local session = dap.session()
  if session then
    M.focus(session)
    dap.continue()
    return
  end
  -- Never replay a configuration that cannot start: a mistyped native executable
  -- would be repeated by every later press. The exec bit only means anything for a
  -- native launch -- gdb/lldb exec an ELF; a managed adapter hands its program to a
  -- runtime (a python/js script carries no exec bit), and an attach never launches
  -- the program at all. So a script or attach target is checked for readability
  -- only, or not at all, instead of being wrongly rejected as gone.
  if last_config then
    local program = last_config.program
    if program and last_config.request ~= "attach" then
      local native = require("dbg.context").profile_of_config(last_config) == "native"
      local broken = vim.fn.filereadable(program) ~= 1 or (native and vim.fn.executable(program) ~= 1)
      if broken then
        require("dbg.notify").warn(vim.fs.basename(program) .. " is gone; choose a configuration again")
        last_config = nil
      end
    end
  end
  if last_config then
    dap.run(vim.deepcopy(last_config))
    return
  end
  dap.continue()
end

-- Without a line table gdb has nothing to step over, so fall back to
-- instruction granularity rather than letting the target run away.
local warned_instruction = false

function M.step(kind)
  local dap = require("dap")
  local session = dap.session()
  if not session then
    require("dbg.notify").info("No debug session is running")
    return
  end
  M.focus(session)
  local frame = session.current_frame
  local sourceless = not (frame and frame.source and (frame.source.path or frame.source.sourceReference))
  local opts = nil
  if sourceless then
    opts = { granularity = "instruction" }
    if not warned_instruction then
      warned_instruction = true
      require("dbg.notify").info("No line table here, stepping one instruction at a time")
    end
  end
  if kind == "over" then
    dap.step_over(opts)
  elseif kind == "into" then
    dap.step_into(opts)
  else
    dap.step_out(opts)
  end
end

-- nvim-dap installs no VimLeavePre handler, so quitting with a session up
-- leaves `gdb -i dap` reparented to init: a launched debuggee keeps running,
-- and against QEMU the orphan holds the gdbstub's single client slot so nothing
-- can attach again.
function M.shutdown()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return
  end
  local sessions = dap.sessions and dap.sessions() or {}
  local any = false
  for _, session in pairs(sessions) do
    any = true
    local attached = (session.config or {}).request == "attach"
    pcall(function()
      if attached then
        session:disconnect({ terminateDebuggee = false })
      else
        session:disconnect({ terminateDebuggee = true })
      end
    end)
  end
  if not any and dap.session() then
    pcall(function()
      dap.disconnect({ terminateDebuggee = (dap.session().config or {}).request ~= "attach" })
    end)
    any = true
  end
  if any then
    -- give the adapter a moment to act on the disconnect before the event loop dies
    vim.wait(700, function()
      return dap.session() == nil
    end, 50)
    pcall(function()
      dap.close()
    end)
  end
  -- Stop exactly the usermode QEMUs this editor launched; an external one the
  -- user attached to is not in the table and is left running.
  pcall(function()
    require("dbg.qemuser").stop_all()
  end)
end

function M.pick()
  local dap = require("dap")
  if dap.session() then
    M.stop()
  end
  last_config = nil
  dap.continue()
end

function M.render()
  local buf = M.buffer()
  local width = panel.width(buf, 100)
  local dap = require("dap")
  local session = dap.session()
  if not session then
    local banner = ui.banner("TARGET", width)
    panel.render(buf, { banner, "", "  No debug session is running." }, ui.banner_hl(0, banner, "TARGET"))
    return
  end
  local cfg = session.config or {}
  local lines, hls = {}, {}
  local banner = ui.banner("TARGET", width, caps.describe(caps_cache))
  lines[1] = banner
  vim.list_extend(hls, ui.banner_hl(0, banner, "TARGET"))

  local function row(k, v)
    lines[#lines + 1] = ("  %-14s%s"):format(k, tostring(v or "-"))
    hls[#hls + 1] = { #lines - 1, 2, 16, "DbgKey" }
  end
  row("name", cfg.name)
  row("adapter", cfg.type)
  row("request", cfg.request)
  row("arch", cfg.arch or (probes["show architecture"] or ""):match('currently "([^"]+)"'))
  row("target", cfg.target or cfg.program)
  row("symbols", cfg.program)
  row("backend", cfg.gdb_bin or cfg.type)
  if cfg.kernel_root then
    row("kernel root", cfg.kernel_root)
  end
  if cfg.type == "gdb_kernel" then
    row("early boot", cfg.kgdb_auto and "GDBTOOLS_AUTO=1, kearly armed" or "inert, commands registered only")
  end
  row("stopped", session.stopped_thread_id and ("thread " .. session.stopped_thread_id) or "running")
  local frame = session.current_frame
  if frame then
    row("frame", ("%s  %s:%s"):format(frame.name, (frame.source or {}).name or "?", frame.line or "?"))
    row("pc", frame.instructionPointerReference)
  end

  local queries = {}
  for cmd, _ in pairs(probes) do
    queries[#queries + 1] = cmd
  end
  table.sort(queries)
  if #queries > 0 then
    lines[#lines + 1] = ""
    local sub = ui.banner("TARGET QUERIES", width, "r to refresh")
    lines[#lines + 1] = sub
    vim.list_extend(hls, ui.banner_hl(#lines - 1, sub, "TARGET QUERIES"))
    for _, cmd in ipairs(queries) do
      local value = tostring(probes[cmd] or "")
      local first = true
      for piece in value:gmatch("[^\n]+") do
        lines[#lines + 1] = ("  %-18s%s"):format(first and cmd or "", piece:sub(1, math.max(20, width - 22)))
        if first then
          hls[#hls + 1] = { #lines - 1, 2, 20, "DbgKey" }
        end
        first = false
      end
      if first then
        lines[#lines + 1] = ("  %-18s%s"):format(cmd, "-")
        hls[#hls + 1] = { #lines - 1, 2, 20, "DbgKey" }
      end
    end
  end
  panel.render(buf, lines, hls)
end

function M.probe()
  local session = gdbq.session()
  if not session then
    probes = {}
    M.render()
    return
  end
  caps.detect(session, function(c)
    caps_cache = c
    local queries = {}
    for _, q in ipairs(ALWAYS) do
      queries[#queries + 1] = q
    end
    if c then
      for _, query in ipairs(BY_KIND[c.kind] or {}) do
        local head = query:match("^(%S+)")
        if c.commands[head] or not head:match("^%a[%w%-]*$") or head == "info" then
          queries[#queries + 1] = query
        end
      end
    end
    gdbq.run_all(queries, function(out)
      probes = {}
      for cmd, text in pairs(out) do
        probes[cmd] = vim.trim(tostring(text))
      end
      vim.schedule(M.render)
    end)
  end)
  M.render()
end

function M.open()
  local buf = M.buffer()
  M.probe()
  panel.show(buf, 16, "Target")
end

return M
