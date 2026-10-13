local M = {}

local EM_NAMES = {
  [40] = "arm",
  [62] = "x86_64",
  [183] = "aarch64",
  [243] = "riscv64",
}

-- Cross-gdb naming varies by distribution and toolchain, and a gdb built with
-- --enable-targets=all ships no cross binary at all. Probe, then fall back on
-- the host gdb only if it is multi-target.
local GDB_CANDIDATES = {
  aarch64 = { "aarch64-linux-gnu-gdb", "aarch64-none-linux-gnu-gdb", "aarch64-none-elf-gdb", "gdb-multiarch" },
  riscv64 = { "riscv64-linux-gnu-gdb", "riscv64-unknown-linux-gnu-gdb", "riscv64-unknown-elf-gdb", "gdb-multiarch" },
  arm = { "arm-none-eabi-gdb", "arm-linux-gnueabihf-gdb", "gdb-multiarch" },
  x86_64 = { "gdb" },
}

-- Kernel trees say "arm64" (ARCH=), the ELF header says "aarch64".
local ARCH_ALIASES = { arm64 = "aarch64", amd64 = "x86_64", riscv = "riscv64" }


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

-- How an ELF carries its DWARF: "embedded", "external", "none", or nil when it
-- is not a readable ELF. Reads the section name table, so any class or endianness.
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
  if names:find("debug_info", 1, true) then
    return "embedded"
  end
  if names:find(".gnu_debuglink", 1, true) or names:find(".debug_sup", 1, true) then
    return "external"
  end
  -- No debug sections and no .symtab means stripped, so a debug package may
  -- still supply it; with .symtab present it was never generated. A build-id
  -- cannot tell these apart: gcc emits one with or without -g.
  if not names:find(".symtab", 1, true) then
    return "stripped"
  end
  return "none"
end

-- Read a /proc file whole. st_size is 0 there, and a fixed-size read of
-- /proc/net/tcp on a busy host silently drops the tail.
local function slurp_proc(path)
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local parts, off = {}, 0
  while true do
    local chunk = vim.uv.fs_read(fd, 262144, off)
    if not chunk or chunk == "" then
      break
    end
    parts[#parts + 1] = chunk
    off = off + #chunk
  end
  vim.uv.fs_close(fd)
  return table.concat(parts)
end

-- listen[port] = true, estab[port] = { inode, ... }.  Both families are read:
-- a client from ::1 appears only in /proc/net/tcp6.
function M.tcp_states()
  local listen, estab = {}, {}
  for _, f in ipairs({ "/proc/net/tcp", "/proc/net/tcp6" }) do
    local data = slurp_proc(f)
    if data then
      for line in data:gmatch("[^\n]+") do
        local col = {}
        for w in line:gmatch("%S+") do
          col[#col + 1] = w
        end
        -- sl local rem st tx:rx tr:when retrnsmt uid timeout inode
        if #col >= 10 then
          local hex = col[2]:match(":(%x+)$")
          local port = hex and tonumber(hex, 16)
          if port then
            if col[4] == "0A" then
              listen[port] = true
            elseif col[4] == "01" then
              estab[port] = estab[port] or {}
              estab[port][#estab[port] + 1] = col[10]
            end
          end
        end
      end
    end
  end
  return listen, estab
end

local reported_unusable = {}
local probed = {}

-- A probe's answer holds until the binary itself changes.
local function identity(what, bin)
  local path = vim.fn.exepath(bin)
  local st = path ~= "" and vim.uv.fs_stat(path) or nil
  return st and ("%s:%s:%d:%d"):format(what, path, st.mtime.sec, st.size) or (what .. ":" .. bin)
end

local function multi_target(bin)
  local key = identity("targets", bin)
  if probed[key] == nil then
    local conf = vim.fn.system({ bin, "--configuration" })
    probed[key] = vim.v.shell_error == 0 and conf:find("--enable-targets=all", 1, true) ~= nil
  end
  return probed[key]
end

local function python_starts(bin)
  local key = identity("python", bin)
  if probed[key] ~= nil then
    return probed[key]
  end
  local ok, proc = pcall(vim.system, { bin, "-nx", "-batch", "-ex", "python gdb.VERSION" }, { text = true })
  local res = ok and proc:wait() or { code = -1, signal = 0, stderr = (tostring(proc):gsub("^[^\n]-:%d+: ", "")) }
  probed[key] = res.code == 0 and (res.signal or 0) == 0
  if probed[key] then
    return true
  end
  if not reported_unusable[bin] then
    reported_unusable[bin] = true
    local err = res.stderr or ""
    local why = err:match("Python Exception[^\n]*") or err:match("[^\n]*not supported[^\n]*") or err:match("%S[^\n]*")
    local status = not ok and "could not start"
      or (res.signal or 0) ~= 0 and ("signal " .. res.signal)
      or ("exit status " .. res.code)
    require("dbg.notify").warn(
      ("%s: 'python gdb.VERSION' failed (%s)%s"):format(bin, status, why and ("\n" .. why) or "")
    )
  end
  return false
end

-- The gdb for an architecture: vim.g.dbg_gdb when the user states one (a name
-- or path, or a table keyed by arch), else the first candidate whose Python
-- starts, else the host gdb if it was built for every target.  nil and the
-- reason when none fits.
function M.gdb_for(arch)
  local key = ARCH_ALIASES[arch] or arch
  local stated = vim.g.dbg_gdb
  if type(stated) == "table" then
    local pick = nil
    for k, v in pairs(stated) do
      if (ARCH_ALIASES[k] or k) == key then
        pick = v
      end
    end
    stated = pick
  end
  if type(stated) == "string" and stated ~= "" then
    if vim.fn.executable(stated) == 1 and python_starts(stated) then
      return stated
    end
    return nil, ("vim.g.dbg_gdb names %s, which is not an executable gdb with Python"):format(stated)
  end
  local cands = GDB_CANDIDATES[key] or { "gdb" }
  for _, cand in ipairs(cands) do
    if vim.fn.executable(cand) == 1 and python_starts(cand) then
      return cand
    end
  end
  -- No cross-gdb: the host one only counts if built for every target.
  if not vim.list_contains(cands, "gdb") and vim.fn.executable("gdb") == 1 then
    if multi_target("gdb") and python_starts("gdb") then
      return "gdb"
    end
  end
  return nil,
    ("no gdb for %s: tried %s and a multi-target host gdb; install one (gdb-multiarch on Debian and Void) or set vim.g.dbg_gdb"):format(
      tostring(arch),
      table.concat(cands, ", ")
    )
end

-- gdb -i dap exists from gdb 14.  true, or false and the reason.
function M.gdb_supports_dap(bin)
  if vim.fn.executable(bin) ~= 1 then
    return false, bin .. " is not installed or not executable"
  end
  local key = identity("dap", bin)
  if probed[key] == nil then
    local ver = vim.fn.system({ bin, "--version" })
    local major = vim.v.shell_error == 0 and tonumber((ver:match("GNU gdb%D*(%d+)"))) or nil
    probed[key] = (major or 0) >= 14
  end
  if not probed[key] then
    return false, bin .. " has no DAP interpreter (gdb -i dap needs gdb 14 or newer)"
  end
  return true
end

local function config_home()
  local conf = vim.env.XDG_CONFIG_HOME
  return (conf and conf ~= "") and conf or ((vim.uv.os_homedir() or "") .. "/.config")
end

-- A tool's checkout as its own installer recorded it in <config>/<tool>/root,
-- or nil.  Read, never searched for.
local function root_pointer(tool)
  local f = config_home() .. "/" .. tool .. "/root"
  if not vim.uv.fs_stat(f) then
    return nil
  end
  local root = (vim.fn.readfile(f)[1] or ""):gsub("%s+$", "")
  return root ~= "" and root or nil, f
end

-- gdbtools' loader: $GDBTOOLS_PATH, else the root gdbtools' setup.sh records.
-- nil when neither is stated; nil and the reason when one is stated and wrong.
function M.gdbtools_loader()
  local env = vim.env.GDBTOOLS_PATH
  if env and env ~= "" then
    local st = vim.uv.fs_stat(env)
    if st and st.type == "file" then
      return env
    end
    return nil, "GDBTOOLS_PATH=" .. env .. " is not a file"
  end
  local root, file = root_pointer("gdbtools")
  if not root then
    return nil
  end
  local loader = root .. "/gdbtools.py"
  local st = vim.uv.fs_stat(loader)
  if st and st.type == "file" then
    return loader
  end
  return nil, ("%s names %s, which has no gdbtools.py (re-run gdbtools' install.sh)"):format(file, root)
end

-- The kbuildlab to run: vim.g.dbg_kbuildlab or $KBUILDLAB when stated, else the
-- one on $PATH, else the checkout its installer recorded -- a session started
-- from a graphical launcher may not have ~/.local/bin on its PATH.
function M.kbuildlab()
  local stated = vim.g.dbg_kbuildlab or vim.env.KBUILDLAB
  if stated and stated ~= "" then
    if vim.fn.executable(stated) == 1 then
      return stated
    end
    return nil, stated .. " (vim.g.dbg_kbuildlab or $KBUILDLAB) is not executable"
  end
  if vim.fn.executable("kbuildlab") == 1 then
    return "kbuildlab"
  end
  local root = root_pointer("kbuildlab")
  local bin = root and (root .. "/bin/kbuildlab")
  if bin and vim.fn.executable(bin) == 1 then
    return bin
  end
  return nil, "kbuildlab is not installed (not on PATH, no " .. config_home() .. "/kbuildlab/root); kernel debugging needs it"
end

-- Run `kbuildlab ARGS` and decode its JSON, null as nil; cb(value) or cb(nil, why).
-- The error is kbuildlab's last message with its continuation lines.
function M.kbuildlab_json(args, env, cb)
  local bin, why = M.kbuildlab()
  if not bin then
    return cb(nil, why)
  end
  local cmd = vim.list_extend({ bin }, args)
  local timeout = 30000
  local ok, proc = pcall(vim.system, cmd, { text = true, env = env, timeout = timeout }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        if res.code == 124 then
          return cb(nil, ("kbuildlab %s did not answer within %d s"):format(args[1], timeout / 1000))
        end
        local err = vim.trim(res.stderr or "")
        local last = nil
        for pos in ("\n" .. err):gmatch("\n()kbuildlab: ") do
          last = pos
        end
        err = last and err:sub(last - 1) or err
        return cb(nil, ("kbuildlab %s failed: %s"):format(args[1], (err:gsub("^kbuildlab: ", ""))))
      end
      local dok, value = pcall(vim.json.decode, res.stdout or "", { luanil = { object = true, array = true } })
      if not dok then
        return cb(nil, "kbuildlab printed something that is not JSON")
      end
      cb(value)
    end)
  end)
  if not ok then
    cb(nil, tostring(proc))
  end
end

return M
