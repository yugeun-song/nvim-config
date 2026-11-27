-- native/windows_wsl_bridge.c caller verification and argument-validation tests.
-- Run by Neovim: nvim -l tests/windows_wsl_bridge/test.lua PATH\TO\windows_wsl_bridge.exe
if vim.fn.has("win32") == 0 then
  print("SKIP windows_wsl_bridge is Windows-only")
  os.exit(0)
end

local exe = arg[1] and vim.fs.normalize(vim.fn.fnamemodify(arg[1], ":p"))

if not exe or not vim.uv.fs_stat(exe) then
  io.stderr:write("usage: nvim -l tests/windows_wsl_bridge/test.lua PATH\\TO\\windows_wsl_bridge.exe\n")
  os.exit(2)
end

local failures = 0
local root = vim.fs.normalize(vim.fn.tempname()) .. "-windows_wsl_bridge"
local system32 = vim.fs.joinpath(vim.env.SystemRoot or "C:/Windows", "System32")
local cmd_exe = vim.fs.joinpath(system32, "cmd.exe")
local host_nvim = vim.v.progpath

vim.fn.mkdir(root, "p")

local function check(ok, what)
  failures = failures + (ok and 0 or 1)
  print((ok and "PASS " or "FAIL ") .. what)
end

local function run(argv, opts)
  opts = opts or {}

  return vim.system(argv, { text = true, cwd = opts.cwd, env = opts.env, timeout = opts.timeout or 10000 }):wait()
end

local function win(path)
  return (path:gsub("/", "\\"))
end

local r = run({ exe, "version" })

check(r.code == 0 and r.stdout:match("^windows_wsl_bridge (%a+) x64\n$") ~= nil, ("version: %q"):format(r.stdout))

r = run({ cmd_exe, "/d", "/c", win(exe) .. " version" })
check(r.code == 4, "version refused via cmd.exe: exit " .. r.code)

-- --embed mode is only for neovide.exe, never nvim.exe or cmd.exe.
for _, argv in ipairs({
  { exe, "--embed" },
  { exe, "--", "/tmp/a.txt", "--embed", "-p" },
  { exe, "--version" },
  { exe, "-v" },
}) do
  r = run(argv)
  check(r.code == 4, ("neovide mode %s refused from nvim.exe: exit %d"):format(argv[2], r.code))
end

-- run-tui argument validation.
for _, case in ipairs({
  { { "run-tui" }, "missing args" },
  { { "run-tui", "-d", "~", "nvim", win(host_nvim) }, "distro starting with dash" },
  { { "run-tui", "arch;id", "~", "nvim", win(host_nvim) }, "distro with semicolon" },
  { { "run-tui", "arch/linux", "~", "nvim", win(host_nvim) }, "distro with slash" },
  { { "run-tui", "arch", "relative", "nvim", win(host_nvim) }, "relative dir" },
  { { "run-tui", "arch", "/tmp\nid", "nvim", win(host_nvim) }, "dir with newline" },
  { { "run-tui", "arch", "~", "sh", win(host_nvim) }, "wsl nvim not nvim or absolute" },
  { { "run-tui", "arch", "~", "/usr/../bin/nvim", win(host_nvim) }, "wsl nvim traversal" },
  { { "run-tui", "arch", "~", "nvim", win(cmd_exe) }, "host nvim is cmd.exe" },
  { { "run-tui", "arch", "~", "nvim", "\\\\server\\share\\nvim.exe" }, "host nvim UNC" },
  { { "run-tui", "arch", "~", "nvim", "C:\\no\\such\\nvim.exe" }, "host nvim missing" },
  { { "run-tui", "arch", "~", "nvim", win(host_nvim), "positional" }, "missing -- before files" },
  { { "run-tui", "arch", "~", "nvim", win(host_nvim), "--", "bad\nfile" }, "file with newline" },
}) do
  r = run(vim.list_extend({ exe }, case[1]))
  check(r.code == 2, ("run-tui refuses %s: exit %d"):format(case[2], r.code))
end

-- spawn-console validation.
local fake_lua = vim.fs.joinpath(root, "evil.lua")
local f = assert(io.open(fake_lua, "wb"))

f:write("print('nope')\n")
f:close()

for _, case in ipairs({
  {
    { "spawn-console", win(cmd_exe), win(fake_lua), "--tui", "--distro", "arch", "--dir-b64", "fg==" },
    "non-nvim exe",
  },
  {
    { "spawn-console", win(host_nvim), win(fake_lua), "--tui", "--distro", "arch", "--dir-b64", "fg==" },
    "script not scripts/wsl.lua",
  },
}) do
  r = run(vim.list_extend({ exe }, case[1]))
  check(r.code == 2, ("spawn-console refuses %s: exit %d"):format(case[2], r.code))
end

vim.fn.delete(root, "rf")
print(("== %d failed"):format(failures))
os.exit(failures == 0 and 0 or 1)
