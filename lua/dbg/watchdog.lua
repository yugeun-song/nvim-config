local M = {}

-- Notices when the QEMU gdbstub goes away.  Losing the target does not look like
-- an error in nvim-dap: gdb keeps its DAP connection and the panels keep showing
-- their last values.
--
-- Liveness is never checked by connecting: QEMU's gdbstub serves one client, so
-- a probe would break the session it is checking.  Signals used instead are what
-- gdb says, and whether the port is still open in the kernel's socket table.

local LOST = {
  "Remote connection closed",
  "Remote communication error",
  "Connection reset by peer",
  "connection closed",
  "Connection timed out",
  "The program is not being run",
  "Remote 'g' packet reply is too long",
  "Cannot execute this command while the target is running",
}

local state = { timer = nil, session = nil, target = nil, misses = 0, announced = false }

local INTERVAL_MS = 4000
-- One miss can be a listener being re-bound; three is gone.
local MISSES_BEFORE_CALLING_IT = 3

local function announce(why)
  if state.announced then
    return
  end
  state.announced = true
  require("dbg.notify").warn(
    ("The target at %s is gone (%s). The panels below are the last state it reported, not the current one."):format(
      state.target or "the gdbstub",
      why
    )
  )
end

function M.saw_text(text)
  if not state.session or state.announced or type(text) ~= "string" then
    return
  end
  for _, needle in ipairs(LOST) do
    if text:find(needle, 1, true) then
      announce(needle)
      return
    end
  end
end

-- host:port out of whatever form the config used.
local function split_target(target)
  local host, port = tostring(target or ""):match("^%[?([^%]]*)%]?:(%d+)$")
  if not port then
    return nil, nil
  end
  return (host == "" and "localhost" or host), tonumber(port)
end

-- Procfs only: no connection, so this is safe while a session is attached.
function M.port_is_listening(port)
  port = tonumber(port)
  if not (port and port == port and port > 0 and port < 65536) then
    return false
  end
  local want = ("%04X"):format(port)
  for _, path in ipairs({ "/proc/net/tcp", "/proc/net/tcp6" }) do
    local fd = io.open(path, "r")
    if fd then
      for line in fd:lines() do
        local local_addr, st = line:match("^%s*%d+:%s+(%S+)%s+%S+%s+(%S%S)")
        if local_addr and st == "0A" and local_addr:match(":(%x+)$") == want then
          fd:close()
          return true
        end
      end
      fd:close()
    end
  end
  return false
end

function M.stop()
  if state.timer then
    pcall(function()
      state.timer:stop()
      state.timer:close()
    end)
  end
  state = { timer = nil, session = nil, target = nil, misses = 0, announced = false }
end

function M.start(session)
  M.stop()
  local cfg = session and session.config or {}
  if cfg.type ~= "gdb_kernel" then
    return
  end
  local _, port = split_target(cfg.target)
  state.session, state.target = session, cfg.target
  if not port then
    return -- unparseable target still gets the message-based half
  end
  local timer = vim.uv.new_timer()
  state.timer = timer
  timer:start(
    INTERVAL_MS,
    INTERVAL_MS,
    vim.schedule_wrap(function()
      local ok, dap = pcall(require, "dap")
      if not ok or dap.session() ~= state.session then
        M.stop()
        return
      end
      if M.port_is_listening(port) then
        state.misses = 0
        return
      end
      state.misses = state.misses + 1
      if state.misses >= MISSES_BEFORE_CALLING_IT then
        announce("the port stopped listening")
        M.stop()
      end
    end)
  )
end

return M
