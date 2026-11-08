-- :checkhealth features.debugging
local status = require("features.feature_status")

local M = {}

local function native()
  local discovery = require("features.debugging.sessions.discovery")
  local gdb, why, broken = discovery.gdb_for()

  if gdb then
    status.available("C, C++ and assembly (gdb)", ("%s, gdb %s"):format(gdb, discovery.gdb_version(gdb)))
  elseif discovery.apple_silicon then
    status.unsupported("C, C++ and assembly (gdb)", "gdb cannot debug programs on Apple silicon")
  else
    status.blocked("C, C++ and assembly (gdb)", why)
  end

  for _, note in ipairs(broken or {}) do
    status.blocked("C, C++ and assembly (gdb)", note)
  end

  if status.MACOS or status.WINDOWS or vim.g.dbg_lldb then
    local lldb, lldb_problem = discovery.lldb()

    if lldb then
      status.available("C and C++ through LLDB", lldb)
    else
      status.blocked("C and C++ through LLDB", lldb_problem)
    end
  end

  return discovery
end

local function qemu_and_linux_kernel(discovery)
  if not status.LINUX then
    status.unsupported("Foreign-architecture programs (QEMU user mode)", "QEMU user mode runs on Linux only")
    status.unsupported("Linux kernels (kbuildlab)", "kbuildlab runs on Linux only")

    return
  end

  local user_mode = require("features.debugging.qemu.user_mode")
  local native_arch = user_mode.norm(vim.uv.os_uname().machine)
  local cross, absent = {}, {}

  for _, arch in ipairs(user_mode.arches()) do
    if arch ~= native_arch then
      local gdb, why, broken = discovery.gdb_for(arch)

      if gdb then
        cross[#cross + 1] = arch .. " " .. gdb
      else
        status.blocked("Foreign-architecture programs", why)
      end

      for _, note in ipairs(broken or {}) do
        status.blocked("Foreign-architecture programs", note)
      end
    end

    if not user_mode.binary(arch) then
      absent[#absent + 1] = "qemu-" .. arch
    end
  end

  if #cross > 0 then
    status.available("Foreign-architecture gdb", table.concat(cross, ", "))
  end

  if #absent == 0 then
    status.available("QEMU user mode", "every architecture")
  else
    status.blocked("QEMU user mode", "missing " .. table.concat(absent, ", "))
  end

  local kbuildlab, kbuildlab_problem = discovery.kbuildlab()

  if kbuildlab then
    status.available("Linux kernels (kbuildlab)", kbuildlab)
  else
    status.blocked("Linux kernels (kbuildlab)", kbuildlab_problem or "kbuildlab not found", {
      "https://github.com/yugeun-song/kbuildlab",
    })
  end

  local loader, loader_problem = discovery.gdbtools_loader()

  if loader then
    status.available("gdbtools", loader)
  else
    status.blocked(
      "gdbtools (optional)",
      loader_problem or "not installed",
      { "https://github.com/yugeun-song/gdbtools" }
    )
  end
end

-- Every adapter nvim-dap has once this configuration set it up, checked by the program it would start.
local function adapters()
  pcall(require, "mason")

  local loaded, err = pcall(require("lazy").load, { plugins = { "nvim-dap" } })
  local ok, dap = pcall(require, "dap")

  if not (loaded and ok) then
    status.blocked("Debug adapters", "nvim-dap does not load: " .. tostring(loaded and dap or err))

    return
  end

  local names = vim.tbl_keys(dap.adapters)

  table.sort(names)
  for _, name in ipairs(names) do
    local adapter = dap.adapters[name]
    local command = type(adapter) == "table"
      and (adapter.command or (type(adapter.executable) == "table" and adapter.executable.command))

    if type(adapter) == "function" then
      status.available("Adapter " .. name, "chosen when a session starts")
    elseif type(command) == "string" then
      if vim.fn.executable(command) == 1 then
        status.available("Adapter " .. name, command)
      else
        status.blocked("Adapter " .. name, command .. " is not on PATH", { ":MasonInstall, or install it yourself" })
      end
    else
      status.available(
        "Adapter " .. name,
        ("connects to %s:%s"):format(adapter.host or "localhost", adapter.port or "?")
      )
    end
  end
end

function M.check()
  vim.health.start("Debugging")
  qemu_and_linux_kernel(native())
  vim.health.start("Debug adapters")
  adapters()
end

return M
