-- js-debug's DAP server, started and ended here rather than by nvim-dap. nvim-dap ends a server adapter's program with
-- SIGHUP on Windows, which libuv does not implement there (ENOSYS): the server kept running and listening on loopback
-- TCP, with no credentials asked, after the session and after Neovim had gone. Mason's launcher is skipped too: on
-- Windows a .cmd calling another .cmd, so ending it ended only cmd.exe. A socket path would close the port, but js-debug
-- opens a child session per target, and nvim-dap connects a child only to a server or an executable adapter.
local M = {}

local servers = {} -- [port] = vim.SystemObj

local function script()
  return vim.fs.joinpath(
    require("features.lsp.mason").ROOT,
    "packages",
    "js-debug-adapter",
    "js-debug",
    "src",
    "dapDebugServer.js"
  )
end

local function free_port()
  local tcp = assert(vim.uv.new_tcp())

  tcp:bind("127.0.0.1", 0)

  local port = tcp:getsockname().port

  tcp:close()

  return port
end

local function stop(port)
  local server = servers[port]

  servers[port] = nil

  if server then
    pcall(function()
      server:kill("sigterm")
    end)
  end
end

-- nvim-dap's adapter: a new server for a session, the root's for a child js-debug starts (startDebugging).
function M.adapter(callback, _, parent)
  if parent and parent.adapter and parent.adapter.port then
    return callback({ type = "server", host = "127.0.0.1", port = parent.adapter.port })
  end

  local port = free_port()
  local ok, server = pcall(vim.system, { "node", script(), tostring(port), "127.0.0.1" }, {
    stdout = false,
    stderr = false,
  }, function()
    servers[port] = nil
  end)

  if not ok then
    vim.notify(("js-debug did not start: %s"):format(server), vim.log.levels.ERROR)

    return
  end

  servers[port] = server
  -- nvim-dap retries the connection while the server comes up (about a second).
  callback({ type = "server", host = "127.0.0.1", port = port, options = { max_retries = 40 } })
end

local watching = false

-- Ends a session's server with the root session, and every server with Neovim.
function M.watch()
  if watching then
    return
  end

  watching = true

  local dap = require("dap")

  dap.listeners.after.event_initialized["js_debug_server"] = function(session)
    local port = session.adapter and session.adapter.port

    if port and servers[port] and not session.parent then
      session.on_close["js_debug_server"] = function()
        stop(port)
      end
    end
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("js_debug_servers", { clear = true }),
    callback = function()
      for port in pairs(servers) do
        stop(port)
      end
    end,
    desc = "End js-debug's servers with Neovim",
  })
end

return M
