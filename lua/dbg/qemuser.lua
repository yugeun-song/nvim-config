-- Usermode cross-architecture debugging over a QEMU user-mode gdbstub.
--
-- The workflow is to study a foreign-arch binary by running, e.g.,
--   qemu-aarch64 -g 1234 -L /usr/aarch64-linux-gnu ./a.out
-- and pointing a cross gdb at :1234. This gives the editor both ends of that: it
-- attaches to a gdbstub already launched, or launches the binary under its own
-- background QEMU and attaches to that. The target arch is read from the ELF, so
-- the right cross gdb, sysroot and QEMU follow from the binary rather than from
-- the user restating what it already declares.
local M = {}
local discover = require("dbg.discover")

-- arch -> usermode QEMU binary and the cross-toolchain sysroot.
--
-- The sysroot is a HOST TOOLCHAIN convention, not a QEMU or hardware fact: Arch
-- and Debian place a cross target's runtime (its ld.so and shared libraries)
-- under /usr/<triple>. QEMU is told it with -L so the guest loader resolves; gdb
-- with `set sysroot` so it reads the matching symbols. It is a default to probe
-- and confirm -- a static binary needs none, and another distro or a custom
-- rootfs puts it elsewhere -- never a constant to trust blindly.
local ARCH = {
  x86_64 = { qemu = "qemu-x86_64", sysroot = nil },
  aarch64 = { qemu = "qemu-aarch64", sysroot = "/usr/aarch64-linux-gnu" },
  riscv64 = { qemu = "qemu-riscv64", sysroot = "/usr/riscv64-linux-gnu" },
  arm = { qemu = "qemu-arm", sysroot = "/usr/arm-linux-gnueabihf" },
  i386 = { qemu = "qemu-i386", sysroot = nil },
}

-- The kernel side names arches "arm64"/"riscv"; the ELF header names them
-- "aarch64"/"riscv64". One spelling reaches the table either way.
local ALIAS = { arm64 = "aarch64", amd64 = "x86_64", riscv = "riscv64", x86 = "i386" }

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

-- The standard sysroot for a cross arch, only when it is actually present; nil
-- otherwise (a static binary, or an unusual layout), so the caller leaves it
-- unset rather than passing a path that is not there.
function M.default_sysroot(arch)
  local m = M.meta(arch)
  if m and m.sysroot and vim.fn.isdirectory(m.sysroot) == 1 then
    return m.sysroot
  end
  return nil
end

-- Background QEMU jobs, keyed by gdbstub port, so teardown stops exactly the
-- process this editor started, never a blanket kill of every qemu on the host.
local jobs = {}

local function listening(port)
  local listen = discover.tcp_states()
  return listen[port] == true
end

-- Start `qemu-<arch> -g <port> [-L <sysroot>] <program> [args...]` in the
-- background; call on_ready once its gdbstub accepts, or on_fail with a reason
-- (no QEMU for the arch, port busy, QEMU exited, or timeout). Exactly one of the
-- two callbacks fires.
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

  -- QEMU opens the gdbstub and waits for a client before running a single guest
  -- instruction, so a short poll for the listening socket suffices.
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
