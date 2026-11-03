local M = {}

local EM_NAMES = {
  [40] = "arm",
  [62] = "x86_64",
  [183] = "aarch64",
  [243] = "riscv64",
}

-- Cross-gdb names vary by distribution; gdb-multiarch and a host gdb built for more targets come after them.
local GDB_CANDIDATES = {
  aarch64 = { "aarch64-linux-gnu-gdb", "aarch64-none-linux-gnu-gdb", "aarch64-none-elf-gdb" },
  riscv64 = { "riscv64-linux-gnu-gdb", "riscv64-unknown-linux-gnu-gdb", "riscv64-unknown-elf-gdb" },
  arm = { "arm-none-eabi-gdb", "arm-linux-gnueabihf-gdb" },
  x86_64 = { "x86_64-linux-gnu-gdb", "x86_64-elf-gdb" },
}

local GDB_ARCH = { aarch64 = "aarch64", riscv64 = "riscv:rv64", arm = "arm", x86_64 = "i386:x86-64" }

-- Kernel trees say "arm64" (ARCH=), the ELF header says "aarch64".
local ARCH_ALIASES = { arm64 = "aarch64", amd64 = "x86_64", riscv = "riscv64", armv7l = "arm", armv6l = "arm" }

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

-- How an ELF carries its DWARF: "embedded", "external", "stripped", "none", or nil
-- when it is not a readable ELF. Reads the section name table, so any class or endianness.
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

  -- No debug sections: without .symtab it was stripped (a debug package may supply it), with one it was never
  -- generated. A build-id cannot tell: gcc emits one with or without -g.
  if not names:find(".symtab", 1, true) then
    return "stripped"
  end

  return "none"
end

local HOST = vim.uv.os_uname().machine
local MAC = vim.fn.has("mac") == 1

local function norm(arch)
  return ARCH_ALIASES[arch] or arch
end

local HOST_ARCH = norm(HOST)

M.apple_silicon = MAC and HOST_ARCH == "aarch64"

-- A probe's answer holds until the binary itself changes.
local function identity(what, bin)
  local path = vim.fn.exepath(bin)
  local st = path ~= "" and vim.uv.fs_stat(path) or nil

  return st and ("%s:%s:%d:%d"):format(what, path, st.mtime.sec, st.size) or (what .. ":" .. bin)
end

-- One gdb run tells whether it starts, whether its Python works, its version and its targets.
local PROBE = "python import gdb, json; print('dbg-probe ' + json.dumps({'version': gdb.VERSION, "
  .. "'arches': gdb.architecture_names() if hasattr(gdb, 'architecture_names') else []}))"

local probes = {}

local function failure(res)
  local err = res.stderr or ""
  local lib = err:match("error while loading shared libraries: ([^:\n]+)")
  local kind, msg = err:match("Python Exception <class '([^']+)'>: ([^\n]*)")

  if lib then
    return ("could not start: %s is missing"):format(lib)
  elseif res.code == 124 then
    return "gave no answer within 10 s"
  elseif (res.signal or 0) ~= 0 then
    return ("crashed (signal %d)"):format(res.signal)
  elseif err:find("Python scripting is not supported", 1, true) then
    return "built without Python, which gdb -i dap needs"
  elseif kind then
    return ("its Python fails (%s: %s)"):format(kind, msg)
  end

  return ("exit status %d: %s"):format(res.code, err:match("%S[^\n]*") or "no output")
end

-- { version, major, arches } or { why }.
local function probe(bin)
  local key = identity("probe", bin)

  if probes[key] then
    return probes[key]
  end

  local started, proc = pcall(vim.system, { bin, "-nx", "-batch", "-ex", PROBE }, { text = true })
  local p

  if not started then
    p = { why = "could not start: " .. tostring(proc):gsub("^[^\n]-:%d+: ", "") }
  else
    local res = proc:wait(10000)
    local json = (res.stdout or ""):match("dbg%-probe (%b{})")
    local ok, info = pcall(vim.json.decode, json or "")

    if json and ok and type(info) == "table" and type(info.version) == "string" then
      local arches = {}

      for _, name in ipairs(info.arches or {}) do
        arches[name] = true
      end

      p = { version = info.version, major = tonumber(info.version:match("^(%d+)")) or 0, arches = arches }
    else
      p = { why = failure(res) }
    end
  end

  probes[key] = p

  return p
end

-- An Intel Mac's gdb debugs programs only when codesigned with the debugger entitlement.
local function codesigned(bin)
  local key = identity("codesign", bin)

  if probes[key] == nil then
    local cmd = { "codesign", "-d", "--entitlements", "-", vim.fn.exepath(bin) }
    local ok, proc = pcall(vim.system, cmd, { text = true })
    local res = ok and proc:wait(5000) or {}

    probes[key] = ((res.stdout or "") .. (res.stderr or "")):find("com.apple.security.cs.debugger", 1, true) ~= nil
  end

  return probes[key]
end

-- Why bin cannot run a DAP session (debugging arch, when given), or nil when it can.
function M.gdb_unusable(bin, arch)
  local key = arch and norm(arch)
  local native = key == HOST_ARCH

  if native and M.apple_silicon then
    return "gdb cannot debug programs on Apple silicon"
  end

  if vim.fn.executable(bin) ~= 1 then
    return "not installed"
  end

  local p = probe(bin)

  if p.why then
    return p.why
  end

  if p.major < 14 then
    return ("gdb %s has no DAP (it came in gdb 14)"):format(p.version)
  end

  if key and GDB_ARCH[key] and not p.arches[GDB_ARCH[key]] then
    return "built without " .. key
  end

  if native and MAC and not codesigned(bin) then
    return "not codesigned for debugging (sourceware.org/gdb/wiki/PermissionsDarwin)"
  end
end

-- gdb -i dap needs gdb 14 with Python. true, or false and the reason.
function M.gdb_supports_dap(bin)
  local why = M.gdb_unusable(bin)

  if why then
    return false, ("%s: %s"):format(bin, why)
  end

  return true
end

function M.gdb_version(bin)
  return probe(bin).version
end

-- MSYS2 puts nothing on PATH.
local MSYS2 = { "C:/msys64/ucrt64/bin", "C:/msys64/mingw64/bin", "C:/msys64/clang64/bin" }

local function candidates(key)
  local names = key == HOST_ARCH and { "gdb", "gdb-multiarch" }
    or vim.list_extend(vim.list_extend({}, GDB_CANDIDATES[key] or {}), { "gdb-multiarch", "gdb" })

  if vim.fn.has("win32") == 1 then
    for _, dir in ipairs(MSYS2) do
      vim.list_extend(names, { dir .. "/gdb.exe", dir .. "/gdb-multiarch.exe" })
    end
  end

  return names
end

local release

-- ID and ID_LIKE of os-release(5).
local function distro()
  if release then
    return release
  end

  release = { id = "", like = {} }

  for _, path in ipairs({ "/etc/os-release", "/usr/lib/os-release" }) do
    local ok, lines = pcall(vim.fn.readfile, path)

    if ok then
      for _, line in ipairs(lines) do
        local k, v = line:match("^(%u[%u_]*)=[\"']?([^\"']*)")

        if k == "ID" then
          release.id = v:lower()
        elseif k == "ID_LIKE" then
          for word in v:lower():gmatch("%S+") do
            release.like[word] = true
          end
        end
      end

      break
    end
  end

  return release
end

-- The package with a gdb for key, as each family shipped it on 2026-11-04.
local function install_hint(key)
  local native = key == HOST_ARCH
  local d = distro()

  local function is(name)
    return d.id == name or d.like[name]
  end

  if vim.fn.has("win32") == 1 then
    return ("pacman -S mingw-w64-ucrt-x86_64-gdb%s in MSYS2"):format(native and "" or "-multiarch")
  elseif MAC then
    return "use the (lldb) configurations, or brew install gdb and codesign it"
  elseif is("debian") or is("ubuntu") then
    return native and "apt install gdb" or "apt install gdb-multiarch"
  elseif is("alpine") then
    return native and "apk add gdb" or "apk add gdb-multiarch"
  elseif is("fedora") or is("rhel") then
    return "dnf install gdb"
  elseif d.id == "opensuse-leap" and key == "riscv64" then
    return "openSUSE Leap's gdb has no riscv64 target"
  elseif is("suse") then
    return "zypper install gdb"
  elseif is("arch") then
    return "pacman -S gdb"
  elseif is("void") then
    return "xbps-install gdb"
  elseif is("nixos") then
    return "add pkgs.gdb"
  end

  return "install gdb 14 or newer built with Python" .. (native and "" or (" and " .. key))
end

-- vim.g.dbg_gdb when stated (a name, a path or a table keyed by arch), else the first candidate that debugs
-- arch (default: the host's). The gdb, nil and the broken candidates it passed; or nil and why none fits.
function M.gdb_for(arch)
  local key = norm(arch or HOST_ARCH)
  local stated = vim.g.dbg_gdb

  if type(stated) == "table" then
    local pick = nil

    for k, v in pairs(stated) do
      if norm(k) == key then
        pick = v
      end
    end

    stated = pick
  end

  if type(stated) == "string" and stated ~= "" then
    local why = M.gdb_unusable(stated, key)

    if why then
      return nil, ("vim.g.dbg_gdb names %s: %s"):format(stated, why)
    end

    return stated, nil, {}
  end

  if key == HOST_ARCH and M.apple_silicon then
    return nil, "gdb cannot debug programs on Apple silicon; C and C++ use the (lldb) configurations"
  end

  local skipped, broken, seen = {}, {}, {}
  local lacking = true

  for _, cand in ipairs(candidates(key)) do
    local path = vim.fn.exepath(cand)

    if path ~= "" and not seen[path] then
      seen[path] = true
      local why = M.gdb_unusable(cand, key)

      if not why then
        return cand, nil, broken
      end

      local note = ("%s: %s"):format(cand, why)
      local missing_target = why:find("^built without") ~= nil

      skipped[#skipped + 1] = note
      lacking = lacking and missing_target
      if not missing_target and not why:find("has no DAP", 1, true) then
        broken[#broken + 1] = note
      end
    end
  end

  if #skipped == 0 then
    return nil, ("no gdb for %s is installed: %s, or set vim.g.dbg_gdb"):format(key, install_hint(key))
  end

  local msg = ("no gdb here debugs %s (%s)"):format(key, table.concat(skipped, "; "))

  return nil, lacking and ("%s: %s, or set vim.g.dbg_gdb"):format(msg, install_hint(key)) or msg
end

local xcode

-- Xcode 16 and its Command Line Tools ship lldb-dap. xcrun runs only once xcode-select names an existing
-- developer directory: without one it opens the tools' install dialog.
local function xcode_lldb_dap()
  if xcode == nil then
    xcode = false
    local ok, proc = pcall(vim.system, { "xcode-select", "-p" }, { text = true })
    local dir = ok and vim.trim(proc:wait(5000).stdout or "") or ""

    if dir ~= "" and vim.uv.fs_stat(dir) then
      local res = vim.system({ "xcrun", "--find", "lldb-dap" }, { text = true }):wait(10000)
      local path = res.code == 0 and vim.trim(res.stdout or "") or ""

      xcode = path ~= "" and path or false
    end
  end

  return xcode or nil
end

-- macOS's C and C++ debugger: vim.g.dbg_lldb, else Xcode's lldb-dap, Mason's codelldb, an lldb-dap on PATH or
-- Homebrew's llvm. All of them speak DAP on stdio.
function M.lldb()
  local stated = vim.g.dbg_lldb

  if type(stated) == "string" and stated ~= "" then
    local path = vim.fn.exepath(stated)

    if path == "" then
      return nil, ("vim.g.dbg_lldb names %s, which is not executable"):format(stated)
    end

    return path
  end

  local cands = {}

  if MAC then
    cands[1] = xcode_lldb_dap()
  end

  vim.list_extend(cands, { vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", "codelldb"), "lldb-dap" })
  if MAC then
    vim.list_extend(cands, { "/opt/homebrew/opt/llvm/bin/lldb-dap", "/usr/local/opt/llvm/bin/lldb-dap" })
  end

  for _, cand in ipairs(cands) do
    local path = vim.fn.exepath(cand)

    if path ~= "" then
      return path
    end
  end

  return nil, "no LLDB adapter: :MasonInstall codelldb, or xcode-select --install for lldb-dap (Xcode 16 tools)"
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

-- vim.g.dbg_kbuildlab or $KBUILDLAB, else the one on $PATH, else the checkout its installer recorded: a
-- graphical launcher may not put ~/.local/bin on PATH.
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

  return nil,
    "kbuildlab is not installed (not on PATH, no " .. config_home() .. "/kbuildlab/root); kernel debugging needs it"
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
