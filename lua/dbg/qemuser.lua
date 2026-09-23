-- Foreign-arch userspace debugging over a QEMU user-mode gdbstub
-- (`qemu-aarch64 -g 1234 -L /usr/aarch64-linux-gnu ./a.out`), either attaching to
-- one already running or launching the binary under a background QEMU. The arch
-- comes from the ELF, and gdb, sysroot and QEMU follow from it.
local M = {}
local discover = require("dbg.discover")

-- The sysroot is a host-toolchain convention (Arch and Debian: /usr/<triple>),
-- probed before use: a static binary needs none and another distro puts it
-- elsewhere.
local ARCH = {
  x86_64 = { qemu = "qemu-x86_64", sysroot = nil },
  aarch64 = { qemu = "qemu-aarch64", sysroot = "/usr/aarch64-linux-gnu" },
  riscv64 = { qemu = "qemu-riscv64", sysroot = "/usr/riscv64-linux-gnu" },
  arm = { qemu = "qemu-arm", sysroot = "/usr/arm-linux-gnueabihf" },
}

-- Kernel spellings (arm64, riscv) map onto the ELF ones the table uses.
local ALIAS = { arm64 = "aarch64", amd64 = "x86_64", riscv = "riscv64" }

function M.norm(arch)
  return ALIAS[arch] or arch
end

function M.meta(arch)
  return ARCH[M.norm(arch or "")]
end

function M.arch_of(program)
  if not program or program == "" then
    return nil
  end
  return discover.elf_arch(program)
end

-- nil when the conventional sysroot is absent, so the caller leaves it unset.
function M.default_sysroot(arch)
  local m = M.meta(arch)
  if m and m.sysroot and vim.fn.isdirectory(m.sysroot) == 1 then
    return m.sysroot
  end
  return nil
end

-- Keyed by gdbstub port, so teardown stops exactly the QEMUs this editor started.
local jobs = {}

local function listening(port)
  local listen = discover.tcp_states()
  return listen[port] == true
end

-- Runs `qemu-<arch> -g <port> [-L <sysroot>] <program> [args...]`; exactly one of
-- on_ready / on_fail(reason) fires.
function M.spawn(cfg, on_ready, on_fail)
  local settled = false
  local function fail(msg)
    if not settled then
      settled = true
      on_fail(msg)
    end
  end
  local function ready()
    if not settled then
      settled = true
      on_ready()
    end
  end

  local m = M.meta(cfg.arch)
  if not m then
    return fail("no usermode QEMU known for arch " .. tostring(cfg.arch))
  end
  if vim.fn.executable(m.qemu) ~= 1 then
    return fail(m.qemu .. " is not installed")
  end
  local port = tonumber(cfg.qemu_port)
  if not port then
    return fail("no gdbstub port given")
  end
  if listening(port) then
    return fail("port " .. port .. " is already in use; attach to it or pick another")
  end

  local cmd = { m.qemu, "-g", tostring(port) }
  if cfg.sysroot and cfg.sysroot ~= "" then
    cmd[#cmd + 1] = "-L"
    cmd[#cmd + 1] = cfg.sysroot
  end
  cmd[#cmd + 1] = cfg.program
  for _, a in ipairs(cfg.qemu_args or {}) do
    cmd[#cmd + 1] = a
  end

  local stderr = {}
  local jid = vim.fn.jobstart(cmd, {
    on_stderr = function(_, data)
      for _, line in ipairs(data or {}) do
        if line ~= "" then
          stderr[#stderr + 1] = line
        end
      end
    end,
    on_exit = function(_, code)
      jobs[port] = nil
      local tail = #stderr > 0 and (": " .. stderr[#stderr]) or ""
      fail(m.qemu .. " exited (" .. code .. ") before the gdbstub was ready" .. tail)
    end,
  })
  if jid <= 0 then
    return fail("could not start " .. m.qemu)
  end
  jobs[port] = jid

  -- QEMU waits for a client before running any guest code, so polling the socket
  -- is enough.
  vim.wait(8000, function()
    return settled or listening(port)
  end, 50)
  if settled then
    return -- on_exit already reported a failure
  end
  if not listening(port) then
    M.stop(port)
    return fail(m.qemu .. " gdbstub did not open on port " .. port .. " in time")
  end
  ready()
end

function M.stop(port)
  local jid = jobs[port]
  if jid then
    jobs[port] = nil
    pcall(vim.fn.jobstop, jid)
  end
end

function M.stop_all()
  for _, jid in pairs(jobs) do
    pcall(vim.fn.jobstop, jid)
  end
  jobs = {}
end

return M
