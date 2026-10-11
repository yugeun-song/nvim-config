-- An all-stop remote target (`target remote`: a QEMU gdbstub, gdbserver) takes no
-- command while it runs. GDB's DAP then refuses breakpoint changes, and a
-- disconnect leaves gdb alive holding the gdbstub. Breakpoint changes are held,
-- the target is interrupted, the held requests are sent and the target resumes;
-- a disconnect halts it first. The interrupt's stop never reaches nvim-dap or
-- its listeners.
local M = {}

local GATED = {
  setBreakpoints = true,
  setFunctionBreakpoints = true,
  setInstructionBreakpoints = true,
  setDataBreakpoints = true,
}

local RESUMES = {
  continue = true,
  next = true,
  stepIn = true,
  stepOut = true,
  stepBack = true,
  reverseContinue = true,
  ["goto"] = true,
}

local PAUSE_WAIT_MS = 2000

local function state(session)
  return session and session.dbg_allstop
end

function M.running(session)
  local st = state(session)
  return st ~= nil and st.running
end

local function stop_timer(st)
  if st.timer then
    st.timer:stop()
    if not st.timer:is_closing() then
      st.timer:close()
    end
    st.timer = nil
  end
end

local function any_thread(session)
  if session.dbg_stopped_thread then
    return session.dbg_stopped_thread
  end
  for id in pairs(session.threads or {}) do
    return id
  end
  return 1
end

local function resume(session, thread_id)
  local st = state(session)
  st.running = true
  st.original(session, "continue", { threadId = thread_id }, function(err)
    if err then
      st.running = false
      require("dbg.notify").error("Could not resume the target after updating breakpoints: " .. tostring(err))
    end
  end)
end

local function flush(session, resume_thread)
  local st = state(session)
  local items = st.queue
  st.queue = {}
  local left = #items
  if left == 0 then
    if resume_thread then
      resume(session, resume_thread)
    end
    return
  end
  for _, item in ipairs(items) do
    st.original(session, item.command, item.args, function(err, resp, seq)
      item.cb(err, resp, seq)
      left = left - 1
      if left == 0 and resume_thread then
        resume(session, resume_thread)
      end
    end)
  end
end

local function settle_halt(st, stopped)
  local waiters = st.halt_waiters
  st.halt_waiters = {}
  for _, cb in ipairs(waiters) do
    cb(stopped)
  end
end

-- Until the next stop: a gdb busy with a long command answers no interrupt either.
local function give_up(session, why)
  local st = state(session)
  stop_timer(st)
  st.pausing = false
  st.uninterruptible = true
  settle_halt(st, false)
  if #st.queue > 0 and not st.warned then
    st.warned = true
    require("dbg.notify").warn(
      ("The target did not stop on interrupt (%s); breakpoint changes apply at its next stop"):format(why)
    )
  end
end

local function interrupt(session)
  local st = state(session)
  if st.pausing or st.uninterruptible then
    return
  end
  st.pausing = true
  st.timer = vim.uv.new_timer()
  st.timer:start(
    PAUSE_WAIT_MS,
    0,
    vim.schedule_wrap(function()
      if st.pausing then
        give_up(session, ("no stop within %d ms"):format(PAUSE_WAIT_MS))
      end
    end)
  )
  st.original(session, "pause", { threadId = any_thread(session) }, function(err)
    if err and st.pausing then
      give_up(session, tostring(err))
    end
  end)
end

-- Stop a running target and keep it stopped, unseen by nvim-dap; `cb(stopped)`
-- runs once it is stopped or the interrupt failed.
function M.halt(session, cb)
  local st = state(session)
  if not st or not st.running then
    cb(true)
    return
  end
  if st.uninterruptible then
    cb(false)
    return
  end
  st.halt_waiters[#st.halt_waiters + 1] = cb
  interrupt(session)
end

-- True when the stop was the interrupt's and nobody else may see it.
local function on_stopped(session, body)
  local st = state(session)
  st.running = false
  st.uninterruptible = false
  stop_timer(st)
  local ours = st.pausing and not st.user_paused and body and body.reason == "pause"
  st.pausing, st.user_paused = false, false
  local halting = #st.halt_waiters > 0
  flush(session, ours and not halting and body.threadId or nil)
  settle_halt(st, true)
  return ours
end

function M.attach(session)
  if state(session) then
    return
  end
  local st = { running = false, queue = {}, halt_waiters = {}, original = session.request }
  session.dbg_allstop = st
  local class_handle = session.handle_body

  session.request = function(self, command, args, cb)
    if GATED[command] and cb and st.running then
      st.queue[#st.queue + 1] = { command = command, args = args, cb = cb }
      interrupt(self)
      return
    end
    if command == "pause" and st.pausing then
      st.user_paused = true
    end
    if RESUMES[command] then
      local was = st.running
      st.running = true
      if cb then
        return st.original(self, command, args, function(err, resp, seq)
          if err then
            st.running = was
          end
          cb(err, resp, seq)
        end)
      end
    end
    return st.original(self, command, args, cb)
  end

  session.handle_body = function(self, body)
    if not (body:find('"stopped"', 1, true) or body:find('"continued"', 1, true)) then
      return class_handle(self, body)
    end
    local ok, msg = pcall(vim.json.decode, body, { luanil = { object = true } })
    if ok and type(msg) == "table" and msg.type == "event" then
      if msg.event == "stopped" and on_stopped(self, msg.body) then
        return
      elseif msg.event == "continued" then
        st.running = true
      end
    end
    return class_handle(self, body)
  end
end

local function drop(session)
  local st = state(session)
  if st then
    stop_timer(st)
    st.queue, st.running, st.pausing = {}, false, false
    settle_halt(st, false)
  end
end

function M.setup(dap)
  dap.listeners.before.event_initialized["dbg_allstop"] = function(session)
    local cfg = session.config or {}
    if require("dbg.context").is_low_level(session) and cfg.target and cfg.target ~= "" then
      M.attach(session)
    end
  end
  for _, name in ipairs({ "event_exited", "event_terminated", "disconnect" }) do
    dap.listeners.after[name]["dbg_allstop"] = drop
  end
end

return M
