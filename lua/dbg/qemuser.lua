-- Foreign-arch userspace debugging over a QEMU user-mode gdbstub, either attaching to one
-- already running or launching the binary under a background QEMU on a private Unix socket.
local M = {}

-- Sysroots follow host-toolchain conventions (Arch/Debian /usr/<triple>, Fedora .../sys-root);
-- a static binary needs none.
local ARCH = {
  x86_64 = { qemu = { "qemu-x86_64", "qemu-x86_64-static" }, sysroot = {} },
  aarch64 = {
    qemu = { "qemu-aarch64", "qemu-aarch64-static" },
    sysroot = { "/usr/aarch64-linux-gnu", "/usr/aarch64-linux-gnu/sys-root" },
  },
  riscv64 = {
    qemu = { "qemu-riscv64", "qemu-riscv64-static" },
    sysroot = { "/usr/riscv64-linux-gnu", "/usr/riscv64-linux-gnu/sys-root" },
  },
  arm = {
    qemu = { "qemu-arm", "qemu-arm-static" },
    sysroot = { "/usr/arm-linux-gnueabihf", "/usr/arm-linux-gnueabihf/sys-root" },
  },
}

local ALIAS = { arm64 = "aarch64", amd64 = "x86_64", riscv = "riscv64" }

function M.norm(arch)
  return ALIAS[arch] or arch
end

function M.meta(arch)
  return ARCH[M.norm(arch or "")]
end

function M.default_sysroot(arch)
  local m = M.meta(arch)
  for _, dir in ipairs(m and m.sysroot or {}) do
    if vim.fn.isdirectory(dir) == 1 then
      return dir
    end
  end
  return nil
end

function M.arches()
  local out = vim.tbl_keys(ARCH)
  table.sort(out)
  return out
end

function M.binary(arch)
  local m = M.meta(arch)
  for _, name in ipairs(m and m.qemu or {}) do
    if vim.fn.executable(name) == 1 then
      return name
    end
  end
  return nil
end

local jobs = {}
local serial = 0

function M.socket_path()
  serial = serial + 1
  return vim.fs.joinpath(vim.fn.stdpath("run"), ("qemu-gdb-%d-%d.sock"):format(vim.fn.getpid(), serial))
end

-- Runs `qemu-<arch> -g <socket> [-L <sysroot>] <program> [args...]`; exactly one of
-- on_ready / on_fail(reason) fires.
function M.spawn(cfg, on_ready, on_fail)
  local settled = false
  local function settle(fn, ...)
    if not settled then
      settled = true
      fn(...)
    end
  end

  local m = M.meta(cfg.arch)
  if not m then
    return settle(on_fail, "no usermode QEMU known for arch " .. tostring(cfg.arch))
  end
  local qemu = M.binary(cfg.arch)
  if not qemu then
    return settle(on_fail, m.qemu[1] .. " is not installed")
  end
  local sock = cfg.qemu_socket
  vim.uv.fs_unlink(sock)

  local cmd = { qemu, "-g", sock }
  if cfg.sysroot and cfg.sysroot ~= "" then
    vim.list_extend(cmd, { "-L", cfg.sysroot })
  end
  cmd[#cmd + 1] = cfg.program
  vim.list_extend(cmd, cfg.qemu_args or {})

  local last_err = ""
  local jid = vim.fn.jobstart(cmd, {
    on_stderr = function(_, data)
      for _, line in ipairs(data or {}) do
        if line ~= "" then
          last_err = line
        end
      end
    end,
    on_exit = function(_, code)
      jobs[sock] = nil
      vim.uv.fs_unlink(sock)
      local tail = last_err ~= "" and (": " .. last_err) or ""
      settle(on_fail, qemu .. " exited (" .. code .. ") before the gdbstub was ready" .. tail)
    end,
  })
  if jid <= 0 then
    return settle(on_fail, "could not start " .. qemu)
  end
  jobs[sock] = jid

  local deadline = vim.uv.now() + 8000
  local timer = assert(vim.uv.new_timer())
  timer:start(
    50,
    50,
    vim.schedule_wrap(function()
      if settled or vim.uv.fs_stat(sock) or vim.uv.now() > deadline then
        if not timer:is_closing() then
          timer:close()
        end
        if not settled and vim.uv.fs_stat(sock) then
          settle(on_ready)
        elseif not settled then
          M.stop(sock)
          settle(on_fail, qemu .. " gdbstub did not open in time")
        end
      end
    end)
  )
end

function M.stop(sock)
  local jid = jobs[sock]
  if jid then
    jobs[sock] = nil
    pcall(vim.fn.jobstop, jid)
  end
  vim.uv.fs_unlink(sock)
end

function M.stop_all()
  for sock, jid in pairs(jobs) do
    pcall(vim.fn.jobstop, jid)
    vim.uv.fs_unlink(sock)
  end
  jobs = {}
end

return M
