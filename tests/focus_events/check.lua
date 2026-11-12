-- Neovim drops a focus event that arrives while a focus autocmd still runs, so nothing here may do its work, or
-- wait, inside one. lua/features/util/windows/lazy_nvim.lua once ran lazy's update check from FocusLost: Neovide
-- loses and regains focus as its window appears, the FocusGained was dropped, and Neovim stayed "unfocused".
--   nvim -l tests/focus_events/check.lua
-- Runs on any system in about 4 s; nothing is written.
local script = vim.fs.normalize(vim.fn.fnamemodify(arg[0], ":p"))
local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(script)))

package.path = vim.fs.joinpath(repo, "lua", "?.lua")
  .. ";"
  .. vim.fs.joinpath(repo, "lua", "?", "init.lua")
  .. ";"
  .. package.path

local failures = 0

local function check(ok, what)
  failures = failures + (ok and 0 or 1)
  print((ok and "PASS " or "FAIL ") .. what)
end

-- lazy's checker as the deferral wraps it: what ran, and whether inside a focus autocmd.
local inside, runs = false, {}

package.loaded["lazy.manage.checker"] = {
  start = function()
    runs[#runs + 1] = { what = "start", inside = inside }
  end,
  check = function()
    runs[#runs + 1] = { what = "check", inside = inside }
  end,
}

local function focus(event)
  inside = true
  vim.api.nvim_exec_autocmds(event, { modeline = false })
  inside = false
end

require("features.util.windows.lazy_nvim").defer_update_checks()
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
require("lazy.manage.checker").start()
check(#runs == 0, "the update check waits")

focus("FocusLost")
check(#runs == 0, "a focus loss does not run it inside the autocmd")
vim.wait(100)
focus("FocusGained")
vim.wait(1300)
check(#runs == 0, "a focus loss of 0.1 s, a window settling, does not run it at all")

focus("FocusLost")
vim.wait(3000, function()
  return #runs > 0
end, 20)

check(
  #runs == 1 and runs[1].what == "start" and not runs[1].inside,
  "without focus for a second: it runs once, from the main loop"
)

focus("FocusGained")
focus("FocusLost")
vim.wait(1300)
check(#runs == 1, "and not again for the same wait")

print(("== %d failed"):format(failures))
vim.cmd.cquit(failures == 0 and 0 or 1)
