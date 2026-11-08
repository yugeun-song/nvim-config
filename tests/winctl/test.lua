-- scripts/winctl.c against what it must do and must refuse. winctl runs only as Neovim's child, so Neovim runs
-- the tests:  nvim -l tests/winctl/test.lua PATH\TO\winctl.exe
-- Windows only; elsewhere it says so and passes. Everything is written under a fresh temporary directory.
if vim.fn.has("win32") == 0 then
  print("SKIP winctl is Windows-only")
  os.exit(0)
end

local exe = arg[1] and vim.fs.normalize(vim.fn.fnamemodify(arg[1], ":p"))

if not exe or not vim.uv.fs_stat(exe) then
  io.stderr:write("usage: nvim -l tests/winctl/test.lua PATH\\TO\\winctl.exe\n")
  os.exit(2)
end

local failures = 0
local root = vim.fs.normalize(vim.fn.tempname()) .. "-winctl"
local system32 = vim.fs.joinpath(vim.env.SystemRoot or "C:/Windows", "System32")
local cmd_exe = vim.fs.joinpath(system32, "cmd.exe")

vim.fn.mkdir(root, "p")

local function check(ok, what)
  failures = failures + (ok and 0 or 1)
  print((ok and "PASS " or "FAIL ") .. what)
end

local function run(argv, opts)
  opts = opts or {}

  return vim.system(argv, { text = true, cwd = opts.cwd, stdin = opts.stdin, timeout = opts.timeout or 10000 }):wait()
end

local function win(path)
  return (path:gsub("/", "\\"))
end

local function write(path, bytes)
  vim.fn.mkdir(vim.fs.dirname(path), "p")

  local f = assert(io.open(path, "wb"))

  f:write(bytes)
  f:close()
end

local function copy(from, to)
  vim.fn.mkdir(vim.fs.dirname(to), "p")
  assert(vim.uv.fs_copyfile(from, to))
end

local r = run({ exe, "version" })

check(r.code == 0 and r.stdout:match("^winctl (%a+) x64\n$") ~= nil, ("version: %q"):format(r.stdout))

r = run({ exe, "state" })
check(r.code == 0 and r.stdout:match("^[01][01]\n$") ~= nil, ("state: %q"):format(r.stdout))

r = run({ exe, "ime-en" })
check(r.code == 0, "ime-en exit " .. r.code)

-- As lua/plugins/input_method/korean_input.lua runs it: no stdout at all.
r = vim.system({ exe, "ime-en" }, { stdout = false, stderr = false }):wait(5000)
check(r.code == 0, "ime-en without a stdout: exit " .. r.code)

local me = tostring(vim.fn.getpid())

for _, argv in ipairs({
  {},
  { "nosuch" },
  { "version", "extra" },
  { "state", "x" },
  { "watch" },
  { "watch", "-5" },
  { "watch", "+5" },
  { "watch", "12x" },
  { "watch", "" },
  { "watch", "99999999999" },
  { "watch", me, "5" },
  { "watch", me, "70000" },
  { "watch", me, "100", "extra" },
  { "raise" },
  { "raise", "0" },
  { "raise", "1e3" },
}) do
  r = run(vim.list_extend({ exe }, argv))
  check(r.code == 2, ("usage for %q: exit %d"):format(table.concat(argv, " "), r.code))
end

r = run({ exe, "watch", tostring(vim.uv.os_getppid()) })
check(r.code == 2, "watch of a process other than its caller refused: exit " .. r.code)

-- watch: a report, pause, e, resume reports again, an unknown byte stops it with 3; EOF ends it with 0.
local lines = {}
local w = vim.system({ exe, "watch", me, "50" }, {
  stdin = true,
  stdout = function(_, data)
    for line in (data or ""):gmatch("[^\n]+") do
      lines[#lines + 1] = line
    end
  end,
})

vim.wait(3000, function()
  return #lines >= 1
end, 20)

w:write("p")
vim.wait(150)
w:write("e")
vim.wait(150)
w:write("r")
vim.wait(3000, function()
  return #lines >= 2
end, 20)

w:write("x")

local wr = w:wait(3000)

check(#lines >= 2 and lines[1]:match("^[01][01]$") and lines[2]:match("^[01][01]$"), "watch reports, again on resume")
check(wr.code == 3, "watch stops on an unknown command: exit " .. tostring(wr.code))

w = vim.system({ exe, "watch", me }, { stdin = true })
vim.wait(300)
w:write(nil)
wr = w:wait(3000)
check(wr.code == 0, "watch ends when its stdin closes: exit " .. tostring(wr.code))

r = run({ exe, "raise", me })
check(r.code == 0 or r.code == 1, "raise runs and returns 0 or 1: exit " .. r.code)

-- Not Neovim's child: a cmd.exe between refuses the subcommands.
r = run({ cmd_exe, "/d", "/c", win(exe) .. " version" })
check(r.code == 4, "refused when cmd.exe, not Neovim, starts it: exit " .. r.code)

local shims = vim.fs.joinpath(root, "shims")
local tool = vim.fs.joinpath(shims, "tool.exe")
local shim_file = vim.fs.joinpath(shims, "tool.shim")

copy(exe, tool)

local function shim(bytes, argv, opts)
  write(shim_file, bytes)

  return run(vim.list_extend({ tool }, argv or { "/d", "/c", "exit 7" }), opts)
end

r = shim(win(cmd_exe), { "/d", "/c", "echo", "one", "two words", "&", "exit", "7" })
check(
  r.code == 7 and r.stdout:find('one "two words"', 1, true) ~= nil,
  ("absolute target, raw arguments, exit code: exit %d, %q"):format(r.code, r.stdout)
)

r = shim(win(cmd_exe) .. "\r\nsecond line ignored")
check(r.code == 7, "CRLF line end, later lines ignored: exit " .. r.code)

copy(cmd_exe, vim.fs.joinpath(root, "bin", "cmd2.exe"))
r = shim("..\\bin\\cmd2.exe", nil, { cwd = system32 })
check(r.code == 7, "relative to the .shim's directory, whatever the current one: exit " .. r.code)
r = shim("../bin/cmd2.exe", nil, { cwd = root })
check(r.code == 7, "relative with forward slashes: exit " .. r.code)

copy(cmd_exe, vim.fs.joinpath(root, "한글 폴더", "cmd.exe"))
r = shim(win(vim.fs.joinpath(root, "한글 폴더", "cmd.exe")))
check(r.code == 7, "a Korean path with a space: exit " .. r.code)

write(vim.fs.joinpath(root, "x.bat"), "@exit /b 7\r\n")
copy(exe, vim.fs.joinpath(shims, "other.exe"))
write(vim.fs.joinpath(shims, "other.shim"), win(cmd_exe))

local drive = cmd_exe:sub(1, 2)

for _, case in ipairs({
  { drive .. "cmd.exe", "drive-relative path" },
  { win(cmd_exe):sub(3), "rooted path" },
  { "\\\\localhost\\" .. drive:sub(1, 1) .. "$" .. win(cmd_exe):sub(3), "UNC share" },
  { "\\\\.\\" .. win(cmd_exe), "device path \\\\.\\" },
  { "\\\\?\\" .. win(cmd_exe), "device path \\\\?\\" },
  { win(cmd_exe) .. ":stream", "alternate data stream" },
  { "C:\\no\\such\\program.exe", "missing program" },
  { win(vim.env.SystemRoot or "C:\\Windows"), "a directory" },
  { win(vim.fs.joinpath(root, "x.bat")), ".bat target" },
  { "tool.exe", "itself" },
  { "other.exe", "another shim" },
  { "", "empty .shim" },
  { "\n" .. win(cmd_exe), "empty first line" },
  { win(cmd_exe):sub(1, 3) .. "Win\tdows", "a control character" },
  { win(cmd_exe):sub(1, 3) .. "Win\0dows", "a NUL byte" },
  { "\239\187\191" .. win(cmd_exe), "a UTF-8 BOM" },
  { "C:\\\195\40\255.exe", "malformed UTF-8" },
  { "C:\\" .. ("a"):rep(1100) .. ".exe", "longer than a .shim may be" },
  { "C:\\" .. ("b"):rep(600) .. ".exe", "longer than a path may be" },
}) do
  r = shim(case[1])
  check(r.code == 127, ("refused: %s (exit %d)"):format(case[2], r.code))
end

-- A command line the OS still takes for the shim, which the shim's own (a longer program path) would exceed.
local long_dir = vim.fs.joinpath(root, ("d"):rep(60), ("e"):rep(60), ("f"):rep(60))

copy(cmd_exe, vim.fs.joinpath(long_dir, "cmd.exe"))

local room = 32767 - #win(tool) - 3 - 8

r = shim(win(vim.fs.joinpath(long_dir, "cmd.exe")), { ("y"):rep(room) })
check(r.code == 127, "refused: the program's command line would pass 32767 characters (exit " .. r.code .. ")")

-- No Neovim among its ancestors: started by WMI, the shim refuses, and cmd.exe never runs.
write(shim_file, win(cmd_exe))

local marker = vim.fs.joinpath(root, "marker.txt")
local wmi = ("Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = '%s /d /c echo ran > %s' } | Out-Null"):format(
  win(tool),
  win(marker)
)

run({ "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", wmi }, { timeout = 30000 })
vim.wait(3000)
check(not vim.uv.fs_stat(marker), "a shim started outside Neovim refuses")

-- Killing the shim ends its program (job object).
write(shim_file, win(vim.fs.joinpath(system32, "PING.EXE")))

local pinger = vim.system({ tool, "-n", "30", "127.0.0.1" })

-- Not inside vim.wait's condition: a nested wait there never sees the query's result.
vim.wait(1500)

local query = run({
  "powershell.exe",
  "-NoProfile",
  "-NonInteractive",
  "-Command",
  -- The program only: a console host can be the shim's child too.
  ("Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq %d -and $_.Name -eq 'PING.EXE' } | ForEach-Object { $_.ProcessId }"):format(
    pinger.pid
  ),
}, { timeout = 30000 })

local child = tonumber(vim.trim(query.stdout or ""))

pinger:kill(9)
pinger:wait(3000)
vim.wait(1000)
check(
  child ~= nil and vim.uv.kill(child, 0) ~= 0,
  ("killing the shim ends its program (child %s; query said %q %q)"):format(
    tostring(child),
    query.stdout or "",
    query.stderr or ""
  )
)

vim.fn.delete(root, "rf")
print(("== %d failed"):format(failures))
os.exit(failures == 0 and 0 or 1)
