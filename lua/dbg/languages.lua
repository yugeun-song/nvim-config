local M = {}

-- Adapters beyond GDB, each registered only when it is actually present, so the
-- configuration picker never offers something that cannot start.
local function mason_package(name)
  local path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "packages", name)
  return vim.uv.fs_stat(path) and path or nil
end

-- Mason only puts its bin directory on PATH once it has loaded, so resolve by
-- path first and fall back to PATH for anything the system provides.
local function mason_bin(name)
  local path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", name)
  if vim.uv.fs_stat(path) then
    return path
  end
  if vim.fn.executable(name) == 1 then
    return name
  end
  return nil
end

local function have(bin)
  return vim.fn.executable(bin) == 1
end

local function first_of(...)
  for _, bin in ipairs({ ... }) do
    if have(bin) then
      return bin
    end
  end
  return nil
end

function M.setup(dap, ask)
  local program, args = ask.program, ask.args

  ---------------------------------------------------------------- rust
  local rust = {}

  local codelldb = mason_bin("codelldb")
  if codelldb then
    dap.adapters.codelldb = {
      type = "server",
      port = "${port}",
      executable = { command = codelldb, args = { "--port", "${port}" } },
    }
    rust[#rust + 1] = {
      name = "Launch (codelldb: Vec/String/Option render properly)",
      type = "codelldb",
      request = "launch",
      program = program("Executable: ", ask.cargo_target),
      args = args("Arguments: "),
      cwd = "${workspaceFolder}",
      stopOnEntry = false,
    }
  end

  if have("lldb-dap") then
    rust[#rust + 1] = {
      name = "Launch (lldb-dap)",
      type = "lldb",
      request = "launch",
      program = program("Executable: ", ask.cargo_target),
      args = args("Arguments: "),
      cwd = "${workspaceFolder}",
      stopOnEntry = false,
      initCommands = ask.rust_init_commands(),
    }
  end

  if have("gdb") then
    rust[#rust + 1] = {
      name = "Launch (gdb: registers, hex view, mappings, pwndbg)",
      type = "gdb",
      request = "launch",
      program = program("Executable: ", ask.cargo_target),
      args = args("Arguments: "),
      cwd = "${workspaceFolder}",
    }
  end

  if #rust > 0 then
    dap.configurations.rust = rust
  end

  ---------------------------------------------------------------- javascript / typescript
  local jsdebug = mason_bin("js-debug-adapter")
  if jsdebug then
    dap.adapters["pwa-node"] = {
      type = "server",
      host = "127.0.0.1",
      port = "${port}",
      executable = { command = jsdebug, args = { "${port}" } },
    }

    -- A .ts file needs a TypeScript-capable runner; .js falls back to plain node.
    local function runtime()
      if vim.fn.expand("%:e"):match("^tsx?$") then
        return first_of("tsx", "ts-node", "bun", "deno")
      end
      return nil
    end

    local js = {
      {
        name = "Launch this file (node)",
        type = "pwa-node",
        request = "launch",
        program = "${file}",
        cwd = "${workspaceFolder}",
        args = args("Arguments: "),
        runtimeExecutable = runtime,
        sourceMaps = true,
        protocol = "inspector",
        console = "integratedTerminal",
        skipFiles = { "<node_internals>/**" },
      },
      {
        name = "Attach to a node process",
        type = "pwa-node",
        request = "attach",
        processId = function()
          return require("dap.utils").pick_process()
        end,
        cwd = "${workspaceFolder}",
        sourceMaps = true,
        skipFiles = { "<node_internals>/**" },
      },
      {
        name = "Attach to node --inspect on a port",
        type = "pwa-node",
        request = "attach",
        address = "127.0.0.1",
        port = function()
          return tonumber(vim.fn.input("Inspector port: ", "9229")) or 9229
        end,
        cwd = "${workspaceFolder}",
        sourceMaps = true,
        skipFiles = { "<node_internals>/**" },
      },
    }
    for _, ft in ipairs({ "javascript", "typescript", "javascriptreact", "typescriptreact" }) do
      dap.configurations[ft] = js
    end
  end

  ---------------------------------------------------------------- python
  local debugpy = mason_package("debugpy")
  if debugpy then
    local venv = vim.fs.joinpath(debugpy, "venv", "bin", "python")
    dap.adapters.python = {
      type = "executable",
      command = vim.uv.fs_stat(venv) and venv or "python3",
      args = { "-m", "debugpy.adapter" },
    }
    dap.configurations.python = {
      {
        name = "Launch this file",
        type = "python",
        request = "launch",
        program = "${file}",
        cwd = "${workspaceFolder}",
        args = args("Arguments: "),
        justMyCode = false,
        console = "integratedTerminal",
      },
      {
        name = "Attach to a running process",
        type = "python",
        request = "attach",
        processId = function()
          return require("dap.utils").pick_process()
        end,
      },
    }
  end
end

return M
