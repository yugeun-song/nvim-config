-- The configuration under random use: first the recorder's own edge cases (recorder.lua), in this process without
-- the configuration; then a headless Neovim with the whole configuration takes a seeded random series of edits,
-- windows, focus changes, writes and plugin loads (driver.lua), and nothing may raise a Lua error or an error
-- notification, switch the input method with no UI, set a key another part of the configuration set, or grow with
-- each repetition of the same work.
--   nvim -l tests/config_fuzz/run.lua [--seed N] [--steps N]
-- Runs on any system with the configuration installed where Neovim loads it (its plugins, Mason's programs); about
-- a minute. Sample files go to a throwaway directory; the configuration's own state is not written (no ShaDa,
-- session, undo or swap file).
local script = vim.fs.normalize(vim.fn.fnamemodify(arg[0], ":p"))
local here = vim.fs.dirname(script)
local repo = vim.fs.dirname(vim.fs.dirname(here))

local failures = 0

local function check(ok, what)
  failures = failures + (ok and 0 or 1)
  print((ok and "PASS " or "FAIL ") .. what)
end

local seed, steps = os.time() % 2147483646 + 1, 300

for i = 1, #arg do
  if arg[i] == "--seed" then
    seed = assert(tonumber(arg[i + 1]), "--seed takes a number")
  elseif arg[i] == "--steps" then
    steps = assert(tonumber(arg[i + 1]), "--steps takes a number")
  end
end

-- 1. The recorder, against the cases that make one lie: its own frames named as the caller, a call recorded twice
-- (vim.keymap.set calls nvim_set_keymap), a wrapper installed twice, an error swallowed or reworded, a failed call
-- remembered, the depth left raised by an error, spellings of one key taken as two, a buffer's mappings outliving it.
local original = {
  set = vim.keymap.set,
  del = vim.keymap.del,
  api_set = vim.api.nvim_set_keymap,
}

local root = vim.fn.tempname()
local cfg, plugin = vim.fs.joinpath(root, "cfg"), vim.fs.joinpath(root, "plugin")

-- Plain calls: a tail call would leave no frame of these files (the last helper is one, on purpose).
local caller_source = [[
local M = {}
function M.set(...) vim.keymap.set(...) end
function M.del(...) vim.keymap.del(...) end
function M.api_set(...) vim.api.nvim_set_keymap(...) end
function M.buf_set(...) vim.api.nvim_buf_set_keymap(...) end
function M.tail_set(...) return vim.keymap.set(...) end
return M
]]

vim.fn.mkdir(cfg, "p")
vim.fn.mkdir(plugin, "p")
vim.fn.writefile(vim.split(caller_source, "\n"), vim.fs.joinpath(cfg, "a.lua"))
vim.fn.writefile(vim.split(caller_source, "\n"), vim.fs.joinpath(cfg, "b.lua"))
vim.fn.writefile(vim.split(caller_source, "\n"), vim.fs.joinpath(plugin, "p.lua"))

local a = dofile(vim.fs.joinpath(cfg, "a.lua"))
local b = dofile(vim.fs.joinpath(cfg, "b.lua"))
local p = dofile(vim.fs.joinpath(plugin, "p.lua"))

vim.g.mapleader = " "

local recorder = dofile(vim.fs.joinpath(here, "recorder.lua"))

recorder.install(cfg)

local wrapped_set = vim.keymap.set

recorder.install(cfg)
check(vim.keymap.set == wrapped_set, "installing again wraps nothing twice")

local function live(mode, lhs, scope)
  return recorder.live[mode .. " " .. recorder.normalize(lhs) .. " " .. tostring(scope or "global")]
end

---@return { mode: string, lhs: string, before: string, after: string, before_defined: string?, after_defined: string? }[]
local function overwrites_since(n)
  return vim.list_slice(recorder.overwrites, n + 1)
end

local calls = recorder.calls

a.set("n", "<Plug>(fuzz-one)", "<Nop>")
check(recorder.calls == calls + 1, "vim.keymap.set is recorded once, not again for the nvim_set_keymap under it")

local entry = live("n", "<Plug>(fuzz-one)")

check(
  entry ~= nil and entry.file == "cfg:a.lua" and entry.line == 2,
  "the caller is the file that called, not a wrapper"
)

local original_error = select(2, pcall(original.set, "Z", "<Plug>(fuzz-bad)", "<Nop>"))
local wrapped_error = select(2, pcall(a.set, "Z", "<Plug>(fuzz-bad)", "<Nop>"))

check(
  original_error ~= nil and wrapped_error == original_error,
  "an error passes through unchanged: " .. tostring(wrapped_error)
)

check(live("n", "<Plug>(fuzz-bad)") == nil and recorder.depth() == 0, "a failed call leaves no mapping and no depth")

calls = recorder.calls
a.set("n", "<Plug>(fuzz-after-error)", "<Nop>")
check(recorder.calls == calls + 1, "and the next call is recorded")

check(
  select("#", vim.api.nvim_set_keymap("n", "<Plug>(fuzz-ret)", "", {})) == 0,
  "the results pass through as they are"
)

-- An error of the recorder's own (here keytrans failing while it records) must not reach the call it watches.
local keytrans, faults = vim.fn.keytrans, #recorder.faults

---@diagnostic disable-next-line: duplicate-set-field
vim.fn.keytrans = function()
  error("a fault of the recorder's, made by this test")
end

local set_despite_fault = pcall(a.set, "n", "<Plug>(fuzz-fault)", "<Nop>")

vim.fn.keytrans = keytrans
check(
  set_despite_fault and vim.fn.maparg("<Plug>(fuzz-fault)", "n") ~= "" and #recorder.faults == faults + 1,
  "an error of the recorder's own reaches no caller: the mapping is set, the fault is kept"
)

table.remove(recorder.faults)

local from_callback

vim.uv.new_timer():start(0, 0, function()
  from_callback = pcall(vim.system, { vim.v.progpath, "--version" })
end)

vim.wait(3000, function()
  return from_callback ~= nil
end)

check(from_callback == true, "a command started in a libuv callback, where the API cannot be asked, passes as it is")

a.set("", "<Plug>(fuzz-map)", "<Nop>")
check(
  live("n", "<Plug>(fuzz-map)")
    and live("x", "<Plug>(fuzz-map)")
    and live("s", "<Plug>(fuzz-map)")
    and live("o", "<Plug>(fuzz-map)")
    and not live("i", "<Plug>(fuzz-map)"),
  'mode "" is :map\'s n, x, s, o'
)

a.set("v", "<Plug>(fuzz-v)", "<Nop>")
a.set("!", "<Plug>(fuzz-bang)", "<Nop>")
check(
  live("x", "<Plug>(fuzz-v)")
    and live("s", "<Plug>(fuzz-v)")
    and live("i", "<Plug>(fuzz-bang)")
    and live("c", "<Plug>(fuzz-bang)"),
  'mode "v" is x and s, "!" is i and c'
)

local n = #recorder.overwrites

-- Each with another rhs: setting the same one again replaces nothing.
a.set("n", "<leader>z", "<Cmd>echo 1<CR>")
b.set("n", "<Space>z", "<Cmd>echo 2<CR>")
a.set("n", "<c-b>", "<Cmd>echo 1<CR>")
b.set("n", "<C-B>", "<Cmd>echo 2<CR>")

local spelled = overwrites_since(n)

check(
  #spelled == 2 and spelled[1].before == "cfg:a.lua:2" and spelled[1].after == "cfg:b.lua:2",
  "<leader>z and <Space>z, <c-b> and <C-B> are one key each, and B setting A's is recorded"
)

check(recorder.normalize("ㅓ") == "ㅓ", "a Hangul lhs keeps its spelling")

a.tail_set("n", "<Plug>(fuzz-tail)", "<Nop>")
check(
  not live("n", "<Plug>(fuzz-tail)").file:find("a.lua", 1, true),
  "a tail call leaves no frame of its file: the caller before it is named"
)

n = #recorder.overwrites
a.set("n", "<Plug>(fuzz-twice)", "<Nop>")
a.set("n", "<Plug>(fuzz-twice)", "<Cmd>echo<CR>")
a.set("n", "<Plug>(fuzz-deleted)", "<Nop>")
a.del("n", "<Plug>(fuzz-deleted)")
b.set("n", "<Plug>(fuzz-deleted)", "<Nop>")
check(#overwrites_since(n) == 0, "one file setting a key again, or a key deleted before another sets it: no overwrite")

calls = recorder.calls
a.del("n", "<Plug>(fuzz-twice)")
check(recorder.calls == calls + 1 and live("n", "<Plug>(fuzz-twice)") == nil, "vim.keymap.del is recorded once")

local del_original = select(2, pcall(original.del, "n", "<Plug>(fuzz-never)"))
local del_wrapped = select(2, pcall(a.del, "n", "<Plug>(fuzz-never)"))

check(del_original ~= nil and del_wrapped == del_original, "deleting a missing mapping fails as it does unwrapped")

local first = vim.api.nvim_get_current_buf()
local other = vim.api.nvim_create_buf(true, false)

a.set("n", "<Plug>(fuzz-local)", "<Nop>", { buffer = 0 })
vim.api.nvim_set_current_buf(other)
a.set("n", "<Plug>(fuzz-true)", "<Nop>", { buffer = true })
b.buf_set(0, "n", "<Plug>(fuzz-api-local)", "", {})

check(
  live("n", "<Plug>(fuzz-local)", first)
    and live("n", "<Plug>(fuzz-true)", other)
    and live("n", "<Plug>(fuzz-api-local)", other),
  "buffer = 0, buffer = true and buffer 0 of the API name the buffer current when set"
)

n = #recorder.overwrites
b.set("n", "<Plug>(fuzz-local)", "<Nop>")
check(#overwrites_since(n) == 0, "a global mapping and a buffer's own of the same lhs are two")

a.set("n", "<Plug>(fuzz-unloaded)", "<Nop>", { buffer = other })
vim.api.nvim_set_current_buf(first)
vim.api.nvim_buf_delete(other, { unload = true })
check(live("n", "<Plug>(fuzz-unloaded)", other) == nil, "an unloaded buffer's mappings are forgotten with it")

local function lost_has(lhs)
  for _, line in ipairs(recorder.lost()) do
    if line:find(lhs, 1, true) then
      return true
    end
  end

  return false
end

a.set("n", "<Plug>(fuzz-lost)", function() end)
vim.cmd("nnoremap <Plug>(fuzz-lost) <Cmd>echo<CR>")
a.set("n", "<Plug>(fuzz-expr)", function()
  return "<Nop>"
end, { expr = true })

a.set("n", "<Plug>(fuzz-string)", "<Cmd>echo 1<CR>")

check(lost_has("<Plug>(fuzz-lost)"), "a mapping replaced by Vimscript's :nnoremap is lost")
check(
  not lost_has("<Plug>(fuzz-expr)") and not lost_has("<Plug>(fuzz-string)"),
  "an expr mapping (whose callback vim.keymap.set wraps) and a string one are not"
)

-- A plugin's helper setting the configuration's functions (LazyVim's keys, Snacks.keymap), or its own.
local function ours_one() end
local function ours_two() end
local theirs = dofile(vim.fs.joinpath(plugin, "p.lua"))

n = #recorder.overwrites
a.set("n", "<Plug>(fuzz-same-fn)", ours_one, { buffer = 0 })
theirs.set("n", "<Plug>(fuzz-same-fn)", ours_one, { buffer = 0 })
check(#overwrites_since(n) == 0, "a plugin's helper setting the same function again replaces nothing")

recorder.install(vim.fs.dirname(script))
a.set("n", "<Plug>(fuzz-our-fn)", ours_one)
theirs.set("n", "<Plug>(fuzz-our-fn)", ours_two)

local helper = overwrites_since(n)[1]

check(
  helper ~= nil and recorder.ours(helper.after, helper.after_defined),
  "a plugin's helper setting a function written in the configuration sets the configuration's mapping"
)

-- A function written in the plugin's file (this file is the configuration's now), over another file's mapping.
n = #recorder.overwrites
a.set("n", "<Plug>(fuzz-their-fn)", ours_one)
theirs.set("n", "<Plug>(fuzz-their-fn)", theirs.del)

local real_conflict = overwrites_since(n)[1]

check(
  real_conflict ~= nil and not recorder.ours(real_conflict.after, real_conflict.after_defined),
  "and one setting its own function over it is still a plugin's"
)

recorder.install(cfg)

p.set("n", "<Plug>(fuzz-plugin)", "<Nop>")
check(live("n", "<Plug>(fuzz-plugin)").file:find("p.lua$") ~= nil, "a file outside the configuration is not cfg:")

check(#vim.api.nvim_list_uis() == 0, "this process has no UI")

local held = #recorder.held_back
local is_held, fake = pcall(function()
  return vim.system({ "/nowhere/windows_ime_helper-1.exe", "ime-english" }):wait()
end)

check(
  is_held and fake.code == 0 and #recorder.held_back == held + 1,
  "with no UI, windows_ime_helper ime-english is held back"
)

check(
  recorder.holds_back({ "/x/windows_ime_helper-1.exe", "raise-window", "1" })
    and not recorder.holds_back({ "/x/windows_ime_helper-1.exe", "input-state" }),
  "raise-window is held back too; input-state, which only reads, is not"
)

-- The wrapper only compares: a command started must not run the configuration's code (which can start commands).
local asked = 0

package.loaded["features.editor.korean_input.backends"] = {
  english_commands = function()
    asked = asked + 1

    return {}
  end,
}

local real = vim.system({ vim.v.progpath, "--version" }, { text = true }):wait()

check(real.code == 0 and real.stdout:find("NVIM", 1, true) ~= nil, "any other command runs as it is")
check(asked == 0, "and starting it calls nothing of the configuration")
package.loaded["features.editor.korean_input.backends"] = nil

recorder.know_switch_commands({ { "fcitx5-remote", "-c" } })
check(
  recorder.holds_back({ "fcitx5-remote", "-c" }) and not recorder.holds_back({ "fcitx5-remote" }),
  "the configuration's own switch commands, as handed over, are held back; other arguments are not"
)

vim.fn.delete(root, "rf")

-- 2. The configuration, in a headless Neovim that loads it.
local config = vim.fn.stdpath("config")

local function same_dir(x, y)
  x, y = vim.uv.fs_realpath(x) or x, vim.uv.fs_realpath(y) or y
  x, y = vim.fs.normalize(x), vim.fs.normalize(y)

  return vim.fn.has("win32") == 1 and x:lower() == y:lower() or x == y
end

if not same_dir(config, repo) then
  check(
    false,
    ("Neovim loads the configuration from %s, not this repository (%s): link or copy it there, or set "):format(
      config,
      repo
    ) .. "NVIM_APPNAME to the name of the directory it is in"
  )

  print(("== %d failed"):format(failures))
  vim.cmd.cquit(1)
end

-- A space, Hangul and & in the samples' path, as users' paths have; the report beside them.
local scratch = vim.fn.tempname()
local samples = vim.fs.joinpath(scratch, "config fuzz 한글 & co")
local report = vim.fs.joinpath(scratch, "report.txt")

vim.fn.mkdir(samples, "p")
print(
  ("INFO seed %d, %d steps: nvim -l tests/config_fuzz/run.lua --seed %d --steps %d"):format(seed, steps, seed, steps)
)

local child = vim
  .system({
    vim.v.progpath,
    "--headless",
    "-i",
    "NONE",
    "--cmd",
    "lua local r = dofile(os.getenv('CONFIG_FUZZ_RECORDER')) package.loaded.config_fuzz_recorder = r "
      .. "r.install(os.getenv('CONFIG_FUZZ_REPO'))",
    "-c",
    "lua dofile(os.getenv('CONFIG_FUZZ_DRIVER'))",
  }, {
    cwd = samples,
    text = true,
    timeout = 900000,
    env = {
      CONFIG_FUZZ_RECORDER = vim.fs.joinpath(here, "recorder.lua"),
      CONFIG_FUZZ_DRIVER = vim.fs.joinpath(here, "driver.lua"),
      CONFIG_FUZZ_REPO = repo,
      CONFIG_FUZZ_SAMPLES = samples,
      CONFIG_FUZZ_SEED = tostring(seed),
      CONFIG_FUZZ_STEPS = tostring(steps),
      CONFIG_FUZZ_OUT = report,
    },
  })
  :wait()

local lines = vim.fn.filereadable(report) == 1 and vim.fn.readfile(report) or {}

vim.fn.delete(scratch, "rf")

local summary = false
local trail = {} -- the last actions begun: where a crash happened

for _, line in ipairs(lines) do
  local kind = line:match("^(%u+) ")

  if kind == "TRY" then
    trail[#trail + 1] = line
    if #trail > 8 then
      table.remove(trail, 1)
    end
  end

  if kind == "FAIL" then
    failures = failures + 1
  end

  if kind == "PASS" or kind == "FAIL" or kind == "INFO" or kind == "STEP" then
    print(line)
  end

  summary = summary or line:find("^DONE") ~= nil
end

if not summary then
  check(
    false,
    ("the headless Neovim stopped before the end (exit %s, signal %s)%s"):format(
      tostring(child.code),
      tostring(child.signal),
      child.code == 124 and ": timed out" or ""
    )
  )

  print("the last actions begun:\n  " .. table.concat(trail, "\n  "))
  print(((child.stderr or ""):gsub("\r", "")):sub(-3000))
end

print(("== %d failed"):format(failures))
vim.cmd.cquit(failures == 0 and 0 or 1)
