-- Debug adapters that are TCP servers (js-debug, codelldb, the Haskell debugger), started and ended here rather than by
-- nvim-dap. nvim-dap starts such a program detached, on Windows outside the job that ends Neovim's children with it,
-- and ends it with SIGHUP, which libuv does not implement on Windows (ENOSYS): the program kept listening, with no
-- credentials asked, after its session and after Neovim. Here a server listens on 127.0.0.1, ends with the session
-- that started it, with a session that never connected, and with Neovim, also when Neovim is killed (Windows: libuv's
-- job; Linux and macOS: a shell that watches Neovim's process). The port is chosen as nvim-dap's ${port} is: free when
-- asked for. On Linux the session is given it once this user's server listens there: a listener of another user, bound
-- between that choice and the server's own bind, would be sent the session, and nvim-dap runs the commands an adapter
-- asks for (runInTerminal). A server that ends before a session connects says so, with its last error output.
local M = {}

local uv = vim.uv
local WIN = vim.fn.has("win32") == 1
local LINUX = uv.os_uname().sysname == "Linux"

-- nvim-dap tries to connect every 250 ms.
local RETRY_MS = 250
-- Linux: how often the socket table is read while a server starts.
local LISTEN_POLL_MS = 50
-- The end of a server's error output kept for the message when it fails.
local ERROR_TAIL = 2000

local servers = {} -- [port] = vim.SystemObj
local claimed = {} -- [port] = true once a session has connected

-- Linux and macOS: the program ends when the watching shell does (stop()) and when Neovim's process is gone. The shell
-- sleeps in the background so that a signal ends it at once, and it exits with the program's status.
local WATCH = table.concat({
  'pid=$1; shift; "$@" & child=$!; nap=',
  "trap 'kill $child $nap 2>/dev/null; exit 143' HUP INT TERM",
  'while kill -0 "$pid" 2>/dev/null && kill -0 "$child" 2>/dev/null; do sleep 2 & nap=$!; wait $nap; done',
  "kill $child 2>/dev/null; wait $child",
}, "; ")

local function free_port()
  local tcp = assert(uv.new_tcp())

  tcp:bind("127.0.0.1", 0)

  local port = tcp:getsockname().port

  tcp:close()

  return port
end

local function stop(port)
  local server = servers[port]

  servers[port], claimed[port] = nil, nil

  if server then
    pcall(function()
      server:kill("sigterm")
    end)
  end
end

local watching = false

-- A root session ends its server; a child session (startDebugging) shares its root's.
local function watch()
  if watching then
    return
  end

  watching = true

  local dap = require("dap")

  dap.listeners.before.initialize["managed_debug_server"] = function(session)
    local port = session.adapter and session.adapter.port

    if port and servers[port] then
      claimed[port] = true

      if not session.parent then
        session.on_close["managed_debug_server"] = function()
          stop(port)
        end
      end
    end
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("managed_debug_servers", { clear = true }),
    callback = function()
      for port in pairs(servers) do
        stop(port)
      end
    end,
    desc = "End the debug servers with Neovim",
  })
end

-- Linux: on_ready once this user's server listens on port. Another user's listener there, or none in time, ends the
-- server instead. Where the socket table cannot be read, on_ready at once.
local function when_listening(spec, port, server, timeout_ms, on_ready)
  local listeners = require("features.dap.core.sessions.gdbstub_watchdog").loopback_listeners
  local me, deadline = uv.getuid(), uv.now() + timeout_ms
  local timer = assert(uv.new_timer())

  local function done()
    if not timer:is_closing() then
      timer:close()
    end
  end

  timer:start(
    0,
    LISTEN_POLL_MS,
    vim.schedule_wrap(function()
      if timer:is_closing() then
        return
      end

      -- Ended: its exit said why.
      if servers[port] ~= server then
        return done()
      end

      local uids = listeners(port)

      if not uids then
        done()

        return on_ready()
      end

      local mine, other = false, nil

      for _, uid in ipairs(uids) do
        if uid == me then
          mine = true
        else
          other = other or uid
        end
      end

      if other then
        done()
        stop(port)
        vim.notify(
          ("%s is not used: another user's process (uid %d) listens on its port %d"):format(spec.name, other, port),
          vim.log.levels.ERROR
        )
      elseif mine then
        done()
        on_ready()
      elseif uv.now() > deadline then
        done()
        stop(port)
        vim.notify(
          ("%s did not listen on 127.0.0.1:%d within %d s"):format(spec.name, port, timeout_ms / 1000),
          vim.log.levels.ERROR
        )
      end
    end)
  )
end

---@class ManagedDebugServer
---@field name string what it is called in a message
---@field cmd fun(port: integer): string[]?, string? the program and its arguments for port; nil and why when absent
---@field env? table<string, string>
---@field retries? integer nvim-dap's connection attempts (default 40, ten seconds)

-- nvim-dap's adapter for spec: a new server for a session, the root's for a child session.
---@param spec ManagedDebugServer
function M.adapter(spec)
  return function(callback, _, parent)
    watch()

    if parent and parent.adapter and parent.adapter.port then
      return callback({ type = "server", host = "127.0.0.1", port = parent.adapter.port })
    end

    local port = free_port()
    local cmd, why = spec.cmd(port)

    if not cmd then
      vim.notify(("%s is not started: %s"):format(spec.name, why or "not found"), vim.log.levels.ERROR)

      return
    end

    if not WIN then
      cmd = vim.list_extend({ "sh", "-c", WATCH, "sh", tostring(uv.os_getpid()) }, cmd)
    end

    local server
    local errors = ""

    local ok, started = pcall(vim.system, cmd, {
      stdout = false,
      stderr = function(_, data)
        if data then
          errors = (errors .. data):sub(-ERROR_TAIL)
        end
      end,
      env = spec.env,
      -- Linux and macOS: a session of its own, or a debugged program that signals its process group (kill 0) would
      -- end Neovim too. Windows keeps it in libuv's job, which ends it with Neovim.
      detach = not WIN,
    }, function(result)
      if servers[port] ~= server then
        return
      end

      local connected = claimed[port]

      servers[port], claimed[port] = nil, nil
      if not connected then
        vim.schedule(function()
          local tail = vim.trim(errors)

          vim.notify(
            ("%s ended (exit %d) before a session connected%s"):format(
              spec.name,
              result.code,
              tail ~= "" and (":\n" .. tail) or ""
            ),
            vim.log.levels.ERROR
          )
        end)
      end
    end)

    if not ok then
      vim.notify(("%s did not start: %s"):format(spec.name, tostring(started)), vim.log.levels.ERROR)

      return
    end

    server = started
    servers[port] = server

    local retries = spec.retries or 40

    -- A session that never connects (the program failed, or listens elsewhere) leaves no server behind.
    vim.defer_fn(function()
      if servers[port] == server and not claimed[port] then
        stop(port)
      end
    end, retries * RETRY_MS + 5000)

    local adapter = { type = "server", host = "127.0.0.1", port = port, options = { max_retries = retries } }

    if not LINUX then
      return callback(adapter)
    end

    when_listening(spec, port, server, retries * RETRY_MS, function()
      callback(adapter)
    end)
  end
end

M._servers = servers

return M
