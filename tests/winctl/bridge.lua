-- lua/features/windows_platform/winctl.lua's own checks, with no winctl involved: what it accepts from a watcher, which
-- files it takes for its build, how it reads an exit status, how it reports, and that it does nothing at all off
-- Windows.
--   nvim -l tests/winctl/bridge.lua      (any system)
local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(arg[0], ":p")))))

package.path = vim.fs.joinpath(repo, "lua", "?.lua") .. ";" .. package.path

local winctl = require("features.windows_platform.winctl")
local failures = 0
local WIN = vim.fn.has("win32") == 1

local function check(ok, what)
  failures = failures + (ok and 0 or 1)
  print((ok and "PASS " or "FAIL ") .. what)
end

local accept = winctl._accept_output
local lines, rest, why

lines, rest, why = accept("", "10\n")
check(#lines == 1 and lines[1] == "10" and rest == "" and not why, "one line")

lines, rest, why = accept("", "1")
check(#lines == 0 and rest == "1" and not why, "half a line waits")
lines, rest, why = accept(rest, "0\n01\n")
check(#lines == 2 and lines[1] == "10" and lines[2] == "01" and rest == "" and not why, "the rest completes it")

for _, bad in ipairs({ "1x\n", "2\n", "100\n", "\n", "10\r\n", "ab\n", " 10\n", "10 \n" }) do
  lines, rest, why = accept("", bad)
  check(why ~= nil and rest == "", ("refused: %q"):format(bad))
end

lines, rest, why = accept("", "10\n1x\n")
check(#lines == 1 and why ~= nil, "lines before a bad one are kept, the bad one refused")

lines, rest, why = accept("", ("1"):rep(65))
check(why ~= nil and rest == "", "a line that never ends is refused")

lines, rest, why = accept(nil, nil)
check(#lines == 0 and rest == "" and not why, "nothing is nothing")

local valid = winctl._valid_exe

check(not valid(nil) and not valid(42), "not a path")
check(not valid("C:/elsewhere/winctl-1-2.exe"), "outside the build directory")
check(
  not valid(
    vim.fs.joinpath(require("features.maintenance.local_storage").path("data", "winctl"), "winctl-1-2.exe.missing")
  ),
  "a name that is not a build"
)

check(
  not valid(
    vim.fs.joinpath(require("features.maintenance.local_storage").path("data", "winctl"), "winctl-dead-beef.exe")
  ),
  "a build that does not exist"
)

local describe = winctl._describe

check(describe({ code = 0 }):find("exit 0", 1, true) ~= nil, "exit 0")
check(describe({ code = 3221225781 }):find("a DLL it imports is missing", 1, true) ~= nil, "a missing DLL is named")
check(describe({ code = 3221225785 }):find("a function it imports is missing", 1, true) ~= nil, "a missing import")
check(describe({ code = 124 }) == "timed out", "a timeout")
check(describe(nil):find("exit %-1") ~= nil, "no result at all")

for _, cmd in ipairs({ "x", "ee", "", "\n", "E" }) do
  check(winctl.send(cmd) == false, ("never sent: %q"):format(cmd))
end

check(winctl.send("e") == false, "no watcher, nothing sent")

local shown = {}

vim.g.did_very_lazy = true
-- Catches what would be shown, instead of showing it.
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(message)
  shown[#shown + 1] = message
end

winctl.report("bridge test: one")
winctl.report("bridge test: one")
winctl.report("bridge test: two")
winctl.report_exit("raise", { code = 1, stderr = "raise: cannot read the lineage\nsecond line" })
winctl.report(nil)
winctl.report("")
vim.wait(100)

check(#shown == 3, "each distinct failure shown once: " .. #shown)
check(shown[3] and shown[3]:find("raise: cannot read the lineage", 1, true) ~= nil, "stderr's first line is shown")
check(#winctl.reports() == 4, "all four kept for :checkhealth")

if not WIN then
  local path, reason = winctl.path()

  check(path == nil and reason == "Windows only", "no helper off Windows")
  check(winctl.watch(function() end) == nil, "no watcher off Windows")
  check(
    not vim.uv.fs_stat(require("features.maintenance.local_storage").path("data", "winctl")),
    "nothing built off Windows"
  )
end

print(("== %d failed"):format(failures))
os.exit(failures == 0 and 0 or 1)
