-- Cross-platform Lua checks for the WSL bridge modules, validators, wt.exe escaping, WSL-side IME bridge,
-- and zero-cost behavior off Windows. Runs in a throwaway XDG root on any system:
--   nvim -l tests/windows_wsl_bridge/lua_check.lua
local script = vim.fs.normalize(vim.fn.fnamemodify(arg[0], ":p"))
local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(script)))

if not os.getenv("WSL_BRIDGE_TEST_ROOT") then
  local root = vim.fn.tempname() .. "-wsl-bridge"
  local env = { WSL_BRIDGE_TEST_ROOT = root }

  for _, kind in ipairs({ "CONFIG", "DATA", "STATE", "CACHE" }) do
    env["XDG_" .. kind .. "_HOME"] = vim.fs.joinpath(root, kind:lower())
  end

  local res = vim.system({ vim.v.progpath, "-l", script }, { env = env, text = true }):wait()

  io.stdout:write(res.stdout or "")
  io.stderr:write(res.stderr or "")
  vim.fs.rm(root, { recursive = true, force = true })
  vim.cmd.cquit(res.code)
end

package.path = vim.fs.joinpath(repo, "lua", "?.lua")
  .. ";"
  .. vim.fs.joinpath(repo, "lua", "?", "init.lua")
  .. ";"
  .. package.path

local wsl = require("features.util.windows.wsl")
local wsl_bridge = require("features.util.windows.wsl_bridge")
local ime_wsl_bridge = require("features.editor.korean_input.wsl_bridge")

local failures = 0
local WIN = vim.fn.has("win32") == 1

local function check(ok, what)
  failures = failures + (ok and 0 or 1)
  print((ok and "PASS " or "FAIL ") .. what)
end

-- 1. Distro parser: English, Korean localized header, UTF-16LE BOM, spaces in name.
local utf8_sample =
  "  NAME            STATE           VERSION\r\n* archlinux       Running         2\r\n  Ubuntu 24.04    Stopped         2\r\n"

local parsed = wsl.parse_distro_list(utf8_sample)

check(#parsed == 2, "parse_distro_list count: " .. #parsed)
check(
  parsed[1]
    and parsed[1].name == "archlinux"
    and parsed[1].default == true
    and parsed[1].state == "Running"
    and parsed[1].version == 2,
  "parsed default archlinux"
)

check(
  parsed[2]
    and parsed[2].name == "Ubuntu 24.04"
    and parsed[2].default == false
    and parsed[2].state == "Stopped"
    and parsed[2].version == 2,
  "parsed space-containing distro"
)

check(wsl.default_distro(parsed) == "archlinux", "default_distro picks starred")

local function encode_utf16le(text)
  local out = {}
  local i = 1
  local len = #text

  while i <= len do
    local b = text:byte(i)
    local cp

    if b < 0x80 then
      cp = b
      i = i + 1
    elseif b < 0xE0 and i + 1 <= len then
      local b2 = text:byte(i + 1)

      cp = (b - 0xC0) * 64 + (b2 - 0x80)
      i = i + 2
    elseif b < 0xF0 and i + 2 <= len then
      local b2, b3 = text:byte(i + 1, i + 2)

      cp = (b - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
      i = i + 3
    elseif i + 3 <= len then
      local b2, b3, b4 = text:byte(i + 1, i + 3)

      cp = (b - 0xF0) * 262144 + (b2 - 0x80) * 4096 + (b3 - 0x80) * 64 + (b4 - 0x80)
      i = i + 4
    else
      cp = 0xFFFD
      i = i + 1
    end

    if cp < 0x10000 then
      out[#out + 1] = string.char(cp % 256, math.floor(cp / 256))
    else
      local v = cp - 0x10000
      local hi = 0xD800 + math.floor(v / 1024)
      local lo = 0xDC00 + (v % 1024)

      out[#out + 1] = string.char(hi % 256, math.floor(hi / 256), lo % 256, math.floor(lo / 256))
    end
  end

  return table.concat(out)
end

local ko_text = "  이름            상태           버전\r\n* archlinux       실행 중         2\r\n"
local ko_utf16 = "\255\254" .. encode_utf16le(ko_text)
local ko_parsed = wsl.parse_distro_list(ko_utf16)

check(
  #ko_parsed == 1 and ko_parsed[1].name == "archlinux" and ko_parsed[1].default == true,
  "parse_distro_list handles UTF-16LE + BOM + localized header"
)

local pair_text = "* archlinux       Running \240\159\152\128      2\r\n"
local pair_parsed = wsl.parse_distro_list("\255\254" .. encode_utf16le(pair_text))

check(
  #pair_parsed == 1 and pair_parsed[1].name == "archlinux" and pair_parsed[1].version == 2,
  "parse_distro_list handles UTF-16LE surrogate pairs"
)

for _, bad_utf16 in ipairs({ "\255\254\0\216", "\255\254\0\220", "\255\254\0", "\0\216" }) do
  check(type(wsl.parse_distro_list(bad_utf16)) == "table", "parse_distro_list survives malformed UTF-16LE")
end

check(#wsl.parse_distro_list("") == 0 and #wsl.parse_distro_list(nil) == 0, "empty distro list")

-- 2. Validators.
check(wsl.validate_distro("archlinux") and wsl.validate_distro("Ubuntu 24.04"), "valid distros")
for _, bad in ipairs({
  "",
  "-d",
  " arch",
  "arch ",
  "arch;id",
  "arch/b",
  "arch\\b",
  'arch"b',
  "arch\nb",
  ("a"):rep(130),
}) do
  check(not wsl.validate_distro(bad), ("rejects distro %q"):format(bad))
end

check(wsl.validate_linux_dir("~") and wsl.validate_linux_dir("/home/user/a & b"), "valid linux dirs")
for _, bad in ipairs({ "", "rel", "~user", "/tmp\nid", "/tmp\0id" }) do
  check(not wsl.validate_linux_dir(bad), ("rejects dir %q"):format(bad))
end

check(wsl.validate_linux_nvim("nvim") and wsl.validate_linux_nvim("/usr/bin/nvim"), "valid linux nvim")
for _, bad in ipairs({ "", "sh", "nvim --cmd", "/usr/../bin/nvim", "/usr/..", "/bin/nvim\nid" }) do
  check(not wsl.validate_linux_nvim(bad), ("rejects nvim %q"):format(bad))
end

check(wsl.validate_linux_file("src/a;b & $(id).c"), "valid linux file")
check(not wsl.validate_linux_file("") and not wsl.validate_linux_file("a\nb"), "rejects empty/control linux file")

-- 3. wt.exe command builder encodes dir/files as base64 and forbids ';' across all arguments.
if not WIN then
  local wt_argv, wt_err = wsl.build_wt_command("C:\\Neovim\\bin\\nvim.exe", "C:\\cfg\\scripts\\wsl.lua", {
    distro = "archlinux",
    dir = "/tmp/a;b & $(calc) 한글",
    nvim = "/usr/bin/nvim",
    files = { "x;y.c", "한글 파일.h" },
    wt_exe = "C:\\WindowsApps\\wt.exe",
  })

  check(wt_argv ~= nil and not wt_err, "build_wt_command succeeds on hostile Linux paths")
  local has_semi = false

  for _, part in ipairs(wt_argv or {}) do
    if part:find(";", 1, true) then
      has_semi = true
    end
  end

  check(not has_semi, "wt.exe argv contains zero semicolons")
end

-- 4. WSL-side IME bridge env validation & stdout protocol parser.
local valid_cfg, verr = ime_wsl_bridge._validate_env(
  "12345",
  "/mnt/c/Users/user/AppData/Local/nvim-data/nvim-config/windows_ime_helper",
  "windows_ime_helper-193cd248da984790-10beb.exe"
)

check(valid_cfg ~= nil and not verr and valid_cfg.ui_pid == "12345", "validates WSL IME bridge env")
for _, bad in ipairs({
  { "0", "/mnt/c/a/nvim-config/windows_ime_helper", "windows_ime_helper-1-2.exe" },
  { "abc", "/mnt/c/a/nvim-config/windows_ime_helper", "windows_ime_helper-1-2.exe" },
  { "123", "relative/nvim-config/windows_ime_helper", "windows_ime_helper-1-2.exe" },
  { "123", "/mnt/c/../evil/nvim-config/windows_ime_helper", "windows_ime_helper-1-2.exe" },
  { "123", "/mnt/c/Windows/System32", "windows_ime_helper-1-2.exe" },
  { "123", "/mnt/c/a/nvim-config/windows_ime_helper", "cmd.exe" },
  { "123", "/mnt/c/a/nvim-config/windows_ime_helper", "../windows_ime_helper-1-2.exe" },
}) do
  check(ime_wsl_bridge._validate_env(bad[1], bad[2], bad[3]) == nil, ("refuses IME env %s / %s"):format(bad[2], bad[3]))
end

local lines, rest, why = ime_wsl_bridge._accept_output("", "10\n")

check(#lines == 1 and lines[1] == "10" and rest == "" and not why, "IME accept_output valid line")
lines, rest, why = ime_wsl_bridge._accept_output("", "bad\n")
check(why ~= nil and rest == "", "IME accept_output rejects invalid line")

-- 5. Zero-cost checks off Windows.
if not WIN then
  local spec = dofile(vim.fs.joinpath(repo, "lua", "plugins", "util", "wsl.lua"))
  local p, pwhy = wsl_bridge.path()

  check(type(spec) == "table" and next(spec) == nil, "plugins/util/wsl.lua returns {} off Windows")
  check(wsl.is_available() == false, "wsl.is_available() is false off Windows")
  check(p == nil and pwhy == "Windows only", "wsl_bridge.path() does nothing off Windows")
  check(
    not vim.uv.fs_stat(require("features.util.storage").path("data", "windows_wsl_bridge")),
    "no bridge directory created off Windows"
  )
end

-- 6. Direct connection defaults (no history table, host UI matching).
check(wsl.recent == nil, "wsl.recent history API is removed")
local prev_neovide = vim.g.neovide

vim.g.neovide = nil
check(wsl.default_mode(true) == "tui", "default_mode uses tui in terminal host even when neovide exists")
vim.g.neovide = true
check(wsl.default_mode(true) == "gui", "default_mode uses gui in Neovide host when neovide exists")
check(wsl.default_mode(false) == "tui", "default_mode falls back to tui without neovide executable")
vim.g.neovide = prev_neovide

print(("== %d failed"):format(failures))
vim.cmd.cquit(failures == 0 and 0 or 1)
