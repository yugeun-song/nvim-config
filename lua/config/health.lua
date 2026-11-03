-- :checkhealth config. ok: supported and ready; warn: supported, something missing; info: not supported here.
local M = {}

local h = vim.health
local machine = vim.uv.os_uname().machine
local OS = vim.fn.has("win32") == 1 and "Windows"
  or vim.fn.has("mac") == 1 and "macOS"
  or vim.fn.has("linux") == 1 and "Linux"
  or vim.uv.os_uname().sysname

local LINUX = OS == "Linux"

-- Runtimes an installed Mason package still needs; :checkhealth mason covers the installers.
local SOURCE_RUNTIME = { npm = { "node" }, gem = { "ruby" }, nuget = { "dotnet" }, composer = { "php" } }
local PACKAGE_RUNTIME = {
  detekt = { "java" },
  ["elixir-ls"] = { "elixir" },
  elp = { "erl" },
  jdtls = { "java" },
  ["js-debug-adapter"] = { "node" },
  ["julia-lsp"] = { "julia" },
  ktlint = { "java" },
}

local function find(tool)
  for _, name in ipairs(type(tool) == "table" and tool or { tool }) do
    if vim.fn.executable(name) == 1 then
      return name
    end
  end
end

local function label(tool)
  return type(tool) == "table" and table.concat(tool, " or ") or tool
end

local function unsupported(name, why)
  h.info(("%s: not supported on %s (%s)"):format(name, OS, why))
end

local function tools(name, list, advice)
  local found, missing = {}, {}

  for _, tool in ipairs(list) do
    local hit = find(tool)

    if hit then
      found[#found + 1] = hit
    else
      missing[#missing + 1] = label(tool)
    end
  end

  if #missing == 0 then
    h.ok(("%s: %s"):format(name, table.concat(found, ", ")))
  else
    h.warn(("%s: missing %s"):format(name, table.concat(missing, ", ")), advice)
  end
end

local function core()
  h.start("Core")
  if vim.fn.has("nvim-0.12") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error("Neovim " .. tostring(vim.version()) .. " is older than 0.12")
  end

  tools("plugins and the statusline tag", { "git" })
  tools("parser builds", { "tree-sitter", { "cc", "gcc", "clang" }, "curl", "tar" })
  tools("picker and grep", { "rg", { "fd", "fdfind" } })
  tools("C and C++ server", { "clangd" }, { ":MasonInstall clangd" })
  tools("C and C++ navigation", { "cscope", "ctags" })
  if vim.fn.has("win32") == 1 then
    unsupported(":Man", "no man command")
  else
    tools(":Man", { "man" })
  end
end

local function debugging()
  h.start("Debugging")
  local discover = require("dbg.discover")
  local gdb, why, broken = discover.gdb_for()

  if gdb then
    h.ok(("C, C++ and assembly: %s (gdb %s)"):format(gdb, discover.gdb_version(gdb)))
  elseif discover.apple_silicon then
    unsupported("gdb", "it cannot debug programs on Apple silicon")
  else
    h.warn("C, C++ and assembly: " .. why)
  end

  for _, note in ipairs(broken or {}) do
    h.warn(note)
  end

  if OS == "macOS" or vim.g.dbg_lldb then
    local lldb, lwhy = discover.lldb()

    if lldb then
      h.ok("C and C++ through LLDB: " .. lldb)
    else
      h.warn("C and C++ through LLDB: " .. lwhy)
    end
  end

  if not LINUX then
    unsupported("QEMU user mode and kernels", "QEMU user mode and kbuildlab run on Linux only")

    return
  end

  local qemuser = require("dbg.qemuser")
  local native = qemuser.norm(machine)
  local cross = {}

  for _, arch in ipairs(qemuser.arches()) do
    if arch ~= native then
      local bin, fwhy, fbroken = discover.gdb_for(arch)

      if bin then
        cross[#cross + 1] = arch .. " " .. bin
      else
        h.warn("foreign targets: " .. fwhy)
      end

      for _, note in ipairs(fbroken or {}) do
        h.warn("foreign targets: " .. note)
      end
    end
  end

  if #cross > 0 then
    h.ok("foreign targets: " .. table.concat(cross, ", "))
  end

  local qemu, absent = {}, {}

  for _, arch in ipairs(qemuser.arches()) do
    local bin = qemuser.binary(arch)

    if bin then
      qemu[#qemu + 1] = bin
    else
      absent[#absent + 1] = "qemu-" .. arch
    end
  end

  if #absent == 0 then
    h.ok("QEMU user mode: " .. table.concat(qemu, ", "))
  else
    h.warn("QEMU user mode: missing " .. table.concat(absent, ", "))
  end

  local kbl, why = discover.kbuildlab()

  if kbl then
    h.ok("kernels: " .. kbl)
  else
    h.warn("kernels: " .. (why or "kbuildlab not found"), { "https://github.com/yugeun-song/kbuildlab" })
  end

  local loader, lwhy = discover.gdbtools_loader()

  if loader then
    h.ok("gdbtools: " .. loader)
  else
    h.warn("gdbtools: " .. (lwhy or "not installed (optional)"), { "https://github.com/yugeun-song/gdbtools" })
  end
end

local function languages()
  h.start("Languages")
  tools("Common Lisp", { "sbcl", "ocicl" })
  tools("Racket", { "racket" })
  tools(
    "Haskell",
    { "ghc", "cabal", { "haskell-language-server-wrapper", "haskell-language-server" }, "hlint" },
    { "https://www.haskell.org/ghcup/" }
  )

  tools("Lean", { "elan" })
  tools("Python lint and format", { "ruff" })
end

local function mason()
  h.start("Mason packages")
  local ok, registry = pcall(require, "mason-registry")

  if not ok then
    h.warn("mason.nvim is not loaded")

    return
  end

  local installed = {}

  for _, name in ipairs(LazyVim.opts("mason.nvim").ensure_installed or {}) do
    local found, pkg = pcall(registry.get_package, name)

    if not found then
      h.warn(name .. ": not in the Mason registry")
    elseif pkg:is_installed() then
      local kind = ((pkg.spec.source or {}).id or ""):match("^pkg:(%w+)/")
      local need = PACKAGE_RUNTIME[name] or SOURCE_RUNTIME[kind]

      if need and not find(need) then
        h.warn(("%s: installed, but %s is missing"):format(name, label(need)))
      else
        installed[#installed + 1] = name
      end
    else
      local installable, can = pcall(pkg.is_installable, pkg)

      if installable and not can then
        unsupported(name, "no Mason build for " .. machine)
      else
        h.warn(name .. ": not installed", { ":MasonInstall " .. name, ":checkhealth mason lists the installers" })
      end
    end
  end

  if #installed > 0 then
    h.ok(("%d installed: %s"):format(#installed, table.concat(installed, ", ")))
  end
end

local function input()
  h.start("Input method and keyboard")
  local ime = require("config.ime")
  local cmd = ime.english_command()

  if cmd then
    h.ok("English on leaving Insert: " .. table.concat(cmd, " "))
  else
    local advice = OS == "macOS" and "macism, im-select or issw"
      or OS == "Windows" and "im-select.exe"
      or "fcitx5, fcitx or ibus"

    h.warn("English on leaving Insert: no IME tool found", { "install " .. advice })
  end

  if not (LINUX or OS == "macOS") then
    unsupported("IME and Caps Lock in the statusline", "they read fcitx5 and a sysfs LED, or macOS tools")

    return
  end

  local src = ime.indicators()

  if src.im then
    h.ok("IME in the statusline: " .. table.concat(src.im.cmd, " "))
  else
    h.warn("IME in the statusline: missing " .. (LINUX and "fcitx5-remote" or "macism, im-select or issw"))
  end

  if src.caps or src.caps_watch then
    h.ok("Caps Lock in the statusline: " .. (src.caps or src.caps_watch[1]))
  else
    h.warn("Caps Lock in the statusline: " .. (LINUX and "no /sys/class/leds/input*::capslock node" or "no osascript"))
  end
end

local function desktop()
  h.start("Desktop")
  local backend, why = require("remote_open").raise_backend()

  if backend then
    h.ok("scripts/open-at.lua raises windows through " .. backend.name)
  elseif why and why:find("GNOME") then
    h.info("scripts/open-at.lua window raise: not supported here (" .. why .. ")")
  else
    h.warn("scripts/open-at.lua window raise: " .. why)
  end

  tools("Open Folder", { "yazi" }, { "https://yazi-rs.github.io/" })
end

function M.check()
  pcall(require, "mason-registry")
  core()
  debugging()
  languages()
  mason()
  input()
  desktop()
end

return M
