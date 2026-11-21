-- js-debug's DAP server, as lua/features/dap/managed_server.lua runs one: on 127.0.0.1, ended with its session and with
-- Neovim. Mason's launcher is skipped: on Windows a .cmd calling another .cmd, so ending it ended only cmd.exe. A socket
-- path would close the port, but js-debug opens a child session per target, and nvim-dap connects a child only to a
-- server or an executable adapter.
local M = {}

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

-- nvim-dap's adapter: a new server for a session, the root's for a child js-debug starts (startDebugging).
M.adapter = require("features.dap.managed_server").adapter({
  name = "js-debug",
  cmd = function(port)
    local server = script()

    if not vim.uv.fs_stat(server) then
      return nil, server .. " is missing: :MasonInstall js-debug-adapter"
    end

    if vim.fn.executable("node") ~= 1 then
      return nil, "node is not on PATH"
    end

    return { "node", server, tostring(port), "127.0.0.1" }
  end,
})

return M
