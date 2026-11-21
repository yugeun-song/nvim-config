local M = {}

-- A lost gdbstub is no error to nvim-dap (gdb keeps its DAP connection), so liveness comes from gdb's output and
-- the socket table, never from connecting: the stub serves one client.

-- gdb's own errors, matched at line start: a guest's log can say "connection closed", and a running target
-- refuses commands while alive.
local LOST = {
  "Remote connection closed",
  "Remote communication error",
  "The program is not being run",
  "Remote 'g' packet reply is too long",
}

-- One watch per session.
local watches = setmetatable({}, { __mode = "k" })

local INTERVAL_MS = 4000
-- One miss can be a listener re-binding.
local MISSES_BEFORE_CALLING_IT = 3

local function announce(watch, why)
  if watch.announced then
    return
  end

  watch.announced = true
  require("features.dap.core.sessions.notifications").warn(
    ("The target at %s is gone (%s). The panels below are the last state it reported, not the current one."):format(
      watch.target or "the gdbstub",
      why
    )
  )
end

function M.saw_text(text, session)
  local watch = session and watches[session]

  if not watch or watch.announced or type(text) ~= "string" then
    return
  end

  for line in text:gmatch("[^\n]+") do
    local head = line:gsub("\27%[[%d;]*m", ""):match("^[^A-Za-z0-9]*(.*)")

    for _, needle in ipairs(LOST) do
      if head:sub(1, #needle) == needle then
        announce(watch, needle)

        return
      end
    end
  end
end

-- gdb's forms: host:port, [host]:port, :port, each also after tcp:, tcp4: or tcp6:.
local function split_target(target)
  local text = tostring(target or ""):gsub("^tcp[46]?:", "")
  local host, port = text:match("^%[?([^%]]*)%]?:(%d+)$")

  if not port then
    return nil, nil
  end

  return (host == "" and "localhost" or host), tonumber(port)
end

-- The hosts that reach this machine's own listeners: the loopback range, and 0.0.0.0 and ::, which Linux connects to
-- the loopback address.
local function is_local(host)
  host = host:lower()

  return host == "localhost"
    or host == "::1"
    or host == "0.0.0.0"
    or host == "::"
    or host:match("^127%.") ~= nil
    or host:match("^::ffff:127%.") ~= nil
end

local LITTLE_ENDIAN = (function()
  local ok, ffi = pcall(require, "ffi")

  return not ok or ffi.abi("le")
end)()

-- Whether a listener bound to addr, as /proc/net/tcp and tcp6 write it (each 32-bit word in host byte order), takes a
-- connection to a loopback address: one bound in the loopback range, or to every address.
local function takes_loopback(addr)
  if LITTLE_ENDIAN then
    addr = addr:gsub("(%x%x)(%x%x)(%x%x)(%x%x)", "%4%3%2%1")
  end

  if #addr == 8 then
    return addr == "00000000" or addr:sub(1, 2) == "7F"
  end

  local mapped = addr:sub(1, 24) == ("0"):rep(20) .. "FFFF"

  return addr == ("0"):rep(32)
    or addr == ("0"):rep(31) .. "1"
    or (mapped and (addr:sub(25, 26) == "7F" or addr:sub(25) == "00000000"))
end

-- The uids of the processes listening on port at an address a loopback connection reaches; nil where the socket
-- table cannot be read (not Linux, or /proc/net closed to apps as on Android).
---@param opts? { paths?: string[] } for tests: other procfs files
---@return integer[]?
function M.loopback_listeners(port, opts)
  local want, uids, read = ("%04X"):format(port), {}, false

  for _, path in ipairs(opts and opts.paths or { "/proc/net/tcp", "/proc/net/tcp6" }) do
    local fd = io.open(path, "r")

    if fd then
      read = true

      for line in fd:lines() do
        local addr, at, st, uid = line:match("^%s*%d+:%s+(%x+):(%x+)%s+%S+%s+(%x%x)%s+%S+%s+%S+%s+%S+%s+(%d+)")

        if addr and at == want and st == "0A" and takes_loopback(addr) then
          uids[#uids + 1] = tonumber(uid)
        end
      end

      fd:close()
    end
  end

  return read and uids or nil
end

-- Linux: why gdb is not to attach to target, a localhost port that another user's process listens on (the guest's QEMU
-- had not bound it, or had ended): gdb serves a remote stub's File-I/O requests, reading and writing this user's
-- files. root's is allowed (sudo qemu-system-x86_64 -s): root may change this user's files anyway. nil for an allowed
-- listener, for anything but a local TCP target, and where procfs cannot tell.
---@param opts? { paths?: string[], uid?: integer } for tests: other procfs files, another user
function M.foreign_listener(target, opts)
  opts = opts or {}

  if not opts.paths and vim.uv.os_uname().sysname ~= "Linux" then
    return nil
  end

  local host, port = split_target(target)

  if not port or not is_local(host) then
    return nil
  end

  local me = opts.uid or vim.uv.getuid()

  for _, uid in ipairs(M.loopback_listeners(port, opts) or {}) do
    if uid ~= me and uid ~= 0 then
      return ("%s is served by another user's process (uid %d): gdb is not attached"):format(target, uid)
    end
  end

  return nil
end

-- Procfs only, so it is safe while a session is attached.
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

function M.stop(session)
  local watch = session and watches[session]

  if not watch then
    return
  end

  watches[session] = nil
  if watch.timer then
    pcall(function()
      watch.timer:stop()
      watch.timer:close()
    end)
  end
end

function M.start(session)
  M.stop(session)
  local cfg = session and session.config or {}

  if
    not require("features.dap.core.sessions.session_profile").is_linux_kernel_config(cfg) or vim.fn.has("linux") == 0
  then
    return
  end

  local host, port = split_target(cfg.target)
  local watch = { timer = nil, target = cfg.target, misses = 0, announced = false }

  watches[session] = watch
  -- Unparseable, or on another host or network namespace (absent from this one's port table): the message-based
  -- half only.
  if not port or not is_local(host) then
    return
  end

  local timer = assert(vim.uv.new_timer())

  watch.timer = timer
  timer:start(
    INTERVAL_MS,
    INTERVAL_MS,
    vim.schedule_wrap(function()
      if watches[session] ~= watch then
        return
      end

      if session.closed then
        M.stop(session)

        return
      end

      if M.port_is_listening(port) then
        watch.misses = 0

        return
      end

      watch.misses = watch.misses + 1
      if watch.misses >= MISSES_BEFORE_CALLING_IT then
        announce(watch, "the port stopped listening")
        M.stop(session)
      end
    end)
  )
end

return M
