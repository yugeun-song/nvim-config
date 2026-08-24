local M = {}

local EM_NAMES = {
  [3] = "i386",
  [40] = "arm",
  [62] = "x86_64",
  [183] = "aarch64",
  [243] = "riscv64",
}

-- Cross-gdb naming is not portable: Debian and Arch ship aarch64-linux-gnu-gdb,
-- other toolchains spell it -none-linux-gnu- or -none-elf-, and a distribution
-- that builds gdb --enable-targets=all ships no cross binary at all.  Probe, and
-- fall back on the host gdb only after checking it really is multi-target.
local GDB_CANDIDATES = {
  aarch64 = { "aarch64-linux-gnu-gdb", "aarch64-none-linux-gnu-gdb", "aarch64-none-elf-gdb", "gdb-multiarch" },
  riscv64 = { "riscv64-linux-gnu-gdb", "riscv64-unknown-linux-gnu-gdb", "riscv64-unknown-elf-gdb", "gdb-multiarch" },
  arm = { "arm-none-eabi-gdb", "arm-linux-gnueabihf-gdb", "gdb-multiarch" },
  x86_64 = { "gdb" },
  i386 = { "gdb" },
}

-- The kernel trees speak "arm64" (their qemu.conf and the kernel's own ARCH=),
-- the ELF header speaks "aarch64".  One name reaches this table either way.
local ARCH_ALIASES = { arm64 = "aarch64", amd64 = "x86_64", riscv = "riscv64", x86 = "i386" }

local function slurp(path, size)
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local data = vim.uv.fs_read(fd, size or 262144, 0)
  vim.uv.fs_close(fd)
  return data
end

local function argv_of(pid)
  local raw = slurp("/proc/" .. pid .. "/cmdline")
  if not raw or raw == "" then
    return nil
  end
  local out = {}
  for field in raw:gmatch("([^%z]+)") do
    out[#out + 1] = field
  end
  return #out > 0 and out or nil
end

function M.elf_arch(path)
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local hdr = vim.uv.fs_read(fd, 20, 0)
  vim.uv.fs_close(fd)
  if not hdr or #hdr < 20 or hdr:sub(1, 4) ~= "\127ELF" then
    return nil
  end
  local little = hdr:byte(6) == 1
  local lo, hi = hdr:byte(19), hdr:byte(20)
  local em = little and (lo + hi * 256) or (hi + lo * 256)
  return EM_NAMES[em] or ("EM_" .. em), em
end

local function uint(str, pos, len, little)
  local v = 0
  if little then
    for i = len, 1, -1 do
      v = v * 256 + str:byte(pos + i - 1)
    end
  else
    for i = 1, len do
      v = v * 256 + str:byte(pos + i - 1)
    end
  end
  return v
end

-- How an ELF carries its DWARF: "embedded", "external" (a separate debug file),
-- "none", or nil when it is not a readable ELF.  The section name string table
-- is read directly, so this holds for any ELF class, endianness and arch.
function M.elf_debug_info(path)
  if not path or path == "" then
    return nil
  end
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local function bail()
    vim.uv.fs_close(fd)
    return nil
  end
  local hdr = vim.uv.fs_read(fd, 64, 0)
  if not hdr or #hdr < 52 or hdr:sub(1, 4) ~= "\127ELF" then
    return bail()
  end
  local wide = hdr:byte(5) == 2
  local little = hdr:byte(6) == 1
  local shoff, shentsize, shnum, shstrndx
  if wide then
    if #hdr < 64 then
      return bail()
    end
    shoff = uint(hdr, 0x29, 8, little)
    shentsize = uint(hdr, 0x3b, 2, little)
    shnum = uint(hdr, 0x3d, 2, little)
    shstrndx = uint(hdr, 0x3f, 2, little)
  else
    shoff = uint(hdr, 0x21, 4, little)
    shentsize = uint(hdr, 0x2f, 2, little)
    shnum = uint(hdr, 0x31, 2, little)
    shstrndx = uint(hdr, 0x33, 2, little)
  end
  if shoff == 0 or shnum == 0 or shentsize == 0 or shstrndx >= shnum then
    return bail()
  end
  local sh = vim.uv.fs_read(fd, shentsize, shoff + shstrndx * shentsize)
  if not sh or #sh < shentsize then
    return bail()
  end
  local stroff, strsize
  if wide then
    stroff = uint(sh, 0x19, 8, little)
    strsize = uint(sh, 0x21, 8, little)
  else
    stroff = uint(sh, 0x11, 4, little)
    strsize = uint(sh, 0x15, 4, little)
  end
  if strsize == 0 then
    return bail()
  end
  local names = vim.uv.fs_read(fd, math.min(strsize, 1048576), stroff)
  vim.uv.fs_close(fd)
  if not names then
    return nil
  end
  if names:find(".debug_info", 1, true) or names:find("debug_info.dwo", 1, true) then
    return "embedded"
  end
  if names:find(".gnu_debuglink", 1, true) or names:find(".debug_sup", 1, true) then
    return "external"
  end
  -- No debug sections and no symbol table either means the binary was stripped,
  -- so debuginfod or a debug package may still supply what was removed.  A
  -- build-id cannot be used to tell these apart: gcc emits one with or without
  -- -g.  With .symtab still present nothing was removed, so the information was
  -- never generated.
  if not names:find(".symtab", 1, true) then
    return "stripped"
  end
  return "none"
end

function M.tcp_states()
  local listen, established = {}, {}
  for _, f in ipairs({ "/proc/net/tcp", "/proc/net/tcp6" }) do
    local data = slurp(f, 1048576)
    if data then
      for line in data:gmatch("[^\n]+") do
        local lport, st = line:match("^%s*%d+:%s+%x+:(%x%x%x%x)%s+%x+:%x+%s+(%x%x)")
        if lport then
          local port = tonumber(lport, 16)
          if st == "0A" then
            listen[port] = true
          elseif st == "01" then
            established[port] = true
          end
        end
      end
    end
  end
  return listen, established
end

function M.parse_qemu(pid, exe, qemu_arch, argv)
  local inst = { pid = pid, exe = exe, qemu_arch = qemu_arch, argv = argv, frozen = false }
  local i = 2
  while i <= #argv do
    local a = argv[i]
    if a == "-gdb" then
      inst.gdb_dev = argv[i + 1]
      i = i + 1
    elseif a == "-s" then
      inst.gdb_dev = inst.gdb_dev or "tcp::1234"
    elseif a == "-S" then
      inst.frozen = true
    elseif a == "-kernel" then
      inst.kernel_image = argv[i + 1]
      i = i + 1
    elseif a == "-append" then
      inst.append = argv[i + 1]
      i = i + 1
    elseif a == "-M" or a == "-machine" then
      inst.machine = argv[i + 1]
      i = i + 1
    elseif a == "-cpu" then
      inst.cpu = argv[i + 1]
      i = i + 1
    elseif a == "-smp" then
      inst.smp = argv[i + 1]
      i = i + 1
    end
    i = i + 1
  end
  if inst.gdb_dev then
    local port = inst.gdb_dev:match("^tcp:.*:(%d+)$")
    if port then
      inst.gdb_port = tonumber(port)
    else
      inst.gdb_other = inst.gdb_dev
    end
  end
  return inst
end

function M.qemu_instances()
  local out = {}
  local dir = vim.uv.fs_scandir("/proc")
  if not dir then
    return out
  end
  while true do
    local name = vim.uv.fs_scandir_next(dir)
    if not name then
      break
    end
    if name:match("^%d+$") then
      local argv = argv_of(name)
      if argv then
        local exe = vim.fs.basename(argv[1] or "")
        local qemu_arch = exe:match("^qemu%-system%-(.+)$")
        if qemu_arch then
          out[#out + 1] = M.parse_qemu(tonumber(name), exe, qemu_arch, argv)
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return (a.gdb_port or 0) < (b.gdb_port or 0)
  end)
  return out
end

function M.qemu_ptys(pid)
  local out = {}
  local dir = vim.uv.fs_scandir("/proc/" .. pid .. "/fd")
  if not dir then
    return out
  end
  local seen = {}
  while true do
    local name = vim.uv.fs_scandir_next(dir)
    if not name then
      break
    end
    local link = vim.uv.fs_readlink("/proc/" .. pid .. "/fd/" .. name)
    if link and link:match("^/dev/pts/%d+$") and not seen[link] then
      seen[link] = true
      out[#out + 1] = link
    end
  end
  table.sort(out)
  return out
end

function M.kernel_root_from_image(image)
  if not image or image == "" then
    return nil, nil
  end
  local root = image:match("^(.*)/arch/[^/]+/boot/.+$")
  if root then
    return root, "derived from qemu -kernel by stripping arch/*/boot"
  end
  if vim.fs.basename(image) == "vmlinux" then
    return vim.fs.dirname(image), "qemu -kernel is the vmlinux itself"
  end
  return nil, nil
end

function M.vmlinux_upward(start)
  if not start or start == "" then
    return nil
  end
  local hit = vim.fs.find("vmlinux", { path = start, upward = true, type = "file", limit = 1 })
  return hit[1]
end

function M.kaslr(inst, kernel_root)
  local append = inst and inst.append
  if append then
    if append:match("%f[%w]nokaslr%f[%W]") then
      return { state = "off", source = "nokaslr on the qemu -append cmdline" }
    end
    if append:match("%f[%w]kaslr%f[%W]") then
      return { state = "on", source = "kaslr on the qemu -append cmdline" }
    end
  end
  local cfg = kernel_root and slurp(kernel_root .. "/.config", 4194304)
  if cfg then
    if cfg:match("[\n^]CONFIG_RANDOMIZE_BASE=y") then
      if append then
        return { state = "on", source = "build has CONFIG_RANDOMIZE_BASE=y and -append carries no nokaslr" }
      end
      return { state = "unknown", source = "build has CONFIG_RANDOMIZE_BASE=y but the boot cmdline is unreadable" }
    end
    if cfg:match("# CONFIG_RANDOMIZE_BASE is not set") then
      return { state = "off", source = "CONFIG_RANDOMIZE_BASE is not set in the build .config" }
    end
  end
  return { state = "unknown", source = "no evidence available" }
end

function M.gdb_for(arch)
  local key = ARCH_ALIASES[arch] or arch
  for _, cand in ipairs(GDB_CANDIDATES[key] or { "gdb" }) do
    if vim.fn.executable(cand) == 1 then
      return cand
    end
  end
  -- No cross-gdb.  The host one is only an answer if it was built for every
  -- target; saying "gdb" regardless would attach an x86 debugger to an arm64
  -- kernel and report nonsense rather than refusing.
  if vim.fn.executable("gdb") == 1 then
    local conf = vim.fn.system({ "gdb", "--configuration" })
    if vim.v.shell_error == 0 and conf:find("--enable-targets=all", 1, true) then
      return "gdb"
    end
  end
  return "gdb"
end

function M.gdb_supports_dap(bin)
  local out = vim.fn.system({ bin, "--configuration" })
  if vim.v.shell_error ~= 0 then
    return false
  end
  local ver = vim.fn.system({ bin, "--version" })
  local major = tonumber((ver:match("GNU gdb%D*(%d+)")))
  return (major or 0) >= 14
end

-- Where the gdbtools loader lives.  Every source of the answer is asked in turn
-- and none of them is a path baked in here, so the repository can be cloned
-- anywhere on any machine.  Absent is a normal answer; the caller decides what
-- that means -- the control-flow panel simply reports that nothing answered.
local function first_readable(paths)
  for _, p in ipairs(paths) do
    if p and vim.uv.fs_stat(p) then
      return p
    end
  end
  return nil
end

local function pointer_file()
  local conf = vim.env.XDG_CONFIG_HOME
  if not conf or conf == "" then
    conf = (vim.uv.os_homedir() or "") .. "/.config"
  end
  local f = conf .. "/gdbtools/root"
  if not vim.uv.fs_stat(f) then
    return nil
  end
  local root = (vim.fn.readfile(f)[1] or ""):gsub("%s+$", "")
  return root ~= "" and (root .. "/gdbtools.py") or nil
end

-- Both repositories are commonly checked out side by side.  Resolving nvim's own
-- config directory through its symlink and looking next to it finds gdbtools
-- without naming a user, a parent directory, or a machine.
local function sibling_checkout()
  local self = vim.uv.fs_realpath(vim.fn.stdpath("config"))
  if not self then
    return nil
  end
  return vim.fs.dirname(self) .. "/gdbtools/gdbtools.py"
end

function M.gdbtools_loader(near)
  local data = vim.env.XDG_DATA_HOME
  if not data or data == "" then
    data = (vim.uv.os_homedir() or "") .. "/.local/share"
  end
  local found = first_readable({ vim.env.GDBTOOLS_PATH })
  if found then
    return found
  end
  if near then
    found = vim.fs.find("gdbtools.py", { path = near, upward = true, type = "file", limit = 1 })[1]
    if found then
      return found
    end
  end
  return first_readable({
    pointer_file(), -- written by gdbtools setup.sh
    sibling_checkout(), -- checked out next to this config
    data .. "/gdbtools/gdbtools.py",
  })
end

return M
