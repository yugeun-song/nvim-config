-- Debug adapters that are TCP servers (js-debug, codelldb, the Haskell debugger), started and ended here rather than by
-- nvim-dap. nvim-dap starts such a program detached, on Windows outside the job that ends Neovim's children with it,
-- and ends it with SIGHUP, which libuv does not implement on Windows (ENOSYS): the program kept listening, with no
-- credentials asked, after its session and after Neovim. Here a server listens on 127.0.0.1, ends with the session
-- that started it, with a session that never connected, and with Neovim, also when Neovim is killed (Windows: libuv's
-- job; Linux and macOS: a shell that watches Neovim's process). The port is chosen as nvim-dap's ${port} is: free when
-- asked for.
local M = {}

local uv = vim.uv
local WIN = vim.fn.has("win32") == 1

-- nvim-dap tries to connect every 250 ms.
local RETRY_MS = 250

local servers = {} -- [port] = vim.SystemObj
local claimed = {} -- [port] = true once a session has connected

-- Linux and macOS: the program ends when the watching shell does (stop()) and when Neovim's process is gone.
local WATCH = [[pid=$1; shift; "$@" & child=$!; trap 'kill $child 2>/dev/null' EXIT HUP INT TERM;]]
  .. [[ while kill -0 "$pid" 2>/dev/null && kill -0 "$child" 2>/dev/null; do sleep 2; done]]

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

    local ok, server = pcall(vim.system, cmd, { stdout = false, stderr = false, env = spec.env }, function()
      servers[port], claimed[port] = nil, nil
    end)

    if not ok then
      vim.notify(("%s did not start: %s"):format(spec.name, tostring(server)), vim.log.levels.ERROR)

      return
    end

    servers[port] = server

    local retries = spec.retries or 40

    -- A session that never connects (the program failed, or listens elsewhere) leaves no server behind.
    vim.defer_fn(function()
      if servers[port] == server and not claimed[port] then
        stop(port)
      end
    end, retries * RETRY_MS + 5000)

    callback({ type = "server", host = "127.0.0.1", port = port, options = { max_retries = retries } })
  end
end

M._servers = servers

return M
