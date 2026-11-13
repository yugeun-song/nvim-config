-- The headless half of tests/config_fuzz/run.lua, in a Neovim that loaded the configuration after recorder.lua: a
-- seeded random series of actions, each followed by the checks; the same work four times over, to find what grows
-- each time; then the mappings. Prints PASS, FAIL, INFO and STEP lines, then DONE.
local recorder = package.loaded.config_fuzz_recorder
local samples = assert(os.getenv("CONFIG_FUZZ_SAMPLES"))
-- A file of its own: Neovim's messages reach stdout too, without line ends, and could run into these lines.
local report = assert(io.open(assert(os.getenv("CONFIG_FUZZ_OUT")), "w"))
local seed = assert(tonumber(os.getenv("CONFIG_FUZZ_SEED")))
local steps = assert(tonumber(os.getenv("CONFIG_FUZZ_STEPS")))

local failures = 0

local function out(line)
  report:write(line, "\n")
  report:flush()
end

local function check(ok, what)
  failures = failures + (ok and 0 or 1)
  out((ok and "PASS " or "FAIL ") .. what)
end

-- Waits, then fires SafeState as the main loop does when idle: a script's waits never are, and the once-only
-- SafeState autocmds that :edit and others add would pile up as if leaked.
local function settle(ms)
  vim.wait(ms, function()
    return false
  end, 10)
  pcall(vim.api.nvim_exec_autocmds, "SafeState", { modeline = false })
end

-- Park-Miller: the same series from the same seed on every Neovim build.
local state = seed % 2147483647

state = state == 0 and 1 or state

local function random(n)
  state = state * 48271 % 2147483647

  return state % n + 1
end

local function pick(list)
  return list[random(#list)]
end

-- Nothing of the configuration's own state is written, and lazy.nvim checks no remote.
vim.o.undofile = false
-- Random typing leaves code a formatter rightly refuses, and 'autowrite' writes it on :bnext: formatting runs
-- only in the write action, on the samples as written first.
vim.g.autoformat = false
vim.o.swapfile = false
pcall(function()
  require("lazy.core.config").options.checker.enabled = false
end)

-- Each replacement of vim.notify (LazyVim's, then Snacks') is wrapped again. LazyVim's first one replays through
-- vim.notify for 500 ms: wrapping it then would loop.
local notes, wrapped = {}, nil

local function watch_notify()
  local current = vim.notify

  if current == wrapped then
    return
  end

  wrapped = function(msg, level, opts)
    notes[#notes + 1] = { level = level or vim.log.levels.INFO, msg = tostring(msg) }

    return current(msg, level, opts)
  end

  vim.notify = wrapped
end

settle(700)
watch_notify()
pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "VeryLazy", modeline = false })
settle(1500)
watch_notify()

-- The commands the configuration switches the input method with, asked once here (no helper build) rather than
-- by the recorder on each command started.
pcall(function()
  recorder.know_switch_commands(require("features.editor.korean_input.backends").english_commands({ build = false }))
end)

-- The samples, in a directory whose path has a space, Hangul and &.
local SAMPLES = {
  ["main.c"] = {
    "#include <stdio.h>",
    "",
    "static int add(int a, int b)",
    "{",
    "    return a + b;",
    "}",
    "",
    "int main(void)",
    "{",
    '    printf("%d\\n", add(1, 2));',
    "    return 0;",
    "}",
  },
  ["util.cpp"] = {
    "#include <vector>",
    "",
    "int sum(const std::vector<int> &v)",
    "{",
    "    return (int)v.size();",
    "}",
  },
  ["util.h"] = { "#pragma once", "int sum_all(void);" },
  ["start.S"] = { ".globl start", "start:", "    mov $1, %eax", "    ret" },
  ["script.py"] = { "def add(a, b):", "    return a + b", "", "print(add(1, 2))" },
  ["notes.md"] = { "# 노트", "", "Some *text* and 한글.", "", "```lua", "local x = 1", "```" },
  ["module.lua"] = { "local M = {}", "", "function M.add(a, b)", "  return a + b", "end", "", "return M" },
  ["data.json"] = { "{", '  "a": [1, 2, 3],', '  "b": { "c": "한글" }', "}" },
  ["run.sh"] = { "#!/bin/sh", 'echo "$1"' },
  ["plain.txt"] = { "plain text", "한글 문장" },
  ["empty.txt"] = {},
  ["한글 이름 & space.lua"] = { "return 1" },
  ["Makefile"] = { "all:", "\techo ok" },
}

local names = {}

for name, lines in pairs(SAMPLES) do
  vim.fn.writefile(lines, vim.fs.joinpath(samples, name))
  names[#names + 1] = name
end

local big = {}

for i = 1, 3000 do
  big[i] = ("int value_%d = %d;"):format(i, i)
end

vim.fn.writefile(big, vim.fs.joinpath(samples, "big.c"))

local crlf = assert(io.open(vim.fs.joinpath(samples, "crlf.c"), "wb"))

crlf:write("int a;\r\nint b;\r\n")
crlf:close()
vim.list_extend(names, { "big.c", "crlf.c", "missing.rs" })
table.sort(names)

local real_samples = vim.uv.fs_realpath(samples) or samples

local function same_path(x, y)
  x, y = vim.fs.normalize(x), vim.fs.normalize(y)

  return vim.fn.has("win32") == 1 and x:lower() == y:lower() or x == y
end

-- A file of the samples, on disk.
local function sample_file(buf)
  local real = vim.uv.fs_realpath(vim.api.nvim_buf_get_name(buf))

  return real ~= nil and same_path(vim.fs.dirname(real), real_samples)
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
end

local function focus(event)
  vim.api.nvim_exec_autocmds(event, { modeline = false })
end

local function close_floats()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

local function listed()
  return vim.tbl_filter(function(buf)
    return vim.bo[buf].buflisted
  end, vim.api.nvim_list_bufs())
end

local TEXT = {
  "hello",
  "한글 입력",
  "{",
  "(x)",
  "\t",
  "if (a) {<CR>b;<CR>}",
  "ㅁㄴㅇ",
  "  trailing  ",
  "<C-w>",
  "<BS><BS>",
}
local KEYS = {
  "gg",
  "G",
  "j",
  "k",
  "ㅓ",
  "ㅏ",
  "dd",
  "u",
  "<C-r>",
  "yyp",
  ">>",
  "<<",
  "ciwword<Esc>",
  "%",
  "zz",
  "*",
  "n",
  "Vjy",
  "<C-v>jl<Esc>",
  "J",
  "x",
  "p",
  "~",
  "zc",
  "zo",
  "zR",
  ":nohlsearch<CR>",
}
local FILETYPES = { "c", "cpp", "asm", "python", "markdown", "lua", "json", "sh", "text", "lisp", "rust", "go", "help" }

-- name = { weight, action }; an action returns what it did, or nil when it does not apply now.
local ACTIONS = {
  edit = {
    8,
    function()
      local name = pick(names)

      vim.cmd.edit(vim.fn.fnameescape(name))

      return "edit " .. name
    end,
  },
  scratch = {
    2,
    function()
      local ft = pick(FILETYPES)

      vim.cmd.enew()
      vim.bo.filetype = ft

      return "new buffer, filetype " .. ft
    end,
  },
  split = {
    3,
    function()
      if #vim.api.nvim_tabpage_list_wins(0) >= 6 then
        return nil
      end

      local how = pick({ "split", "vsplit" })

      vim.cmd(how)

      return how
    end,
  },
  close = {
    3,
    function()
      if vim.fn.winnr("$") < 2 then
        return nil
      end

      vim.cmd.close()

      return "close a window"
    end,
  },
  tab = {
    1,
    function()
      if vim.fn.tabpagenr("$") > 1 and random(2) == 1 then
        vim.cmd.tabclose()

        return "tabclose"
      end

      if vim.fn.tabpagenr("$") >= 4 then
        return nil
      end

      vim.cmd.tabnew()

      return "tabnew"
    end,
  },
  buffer = {
    3,
    function()
      local how = pick({ "bnext", "bprevious" })

      vim.cmd(how)

      return how
    end,
  },
  delete = {
    2,
    function()
      if #listed() < 3 then
        return nil
      end

      local how = pick({ "bdelete!", "bwipeout!" })

      vim.cmd(how)

      return how
    end,
  },
  focus = {
    3,
    function()
      local how = pick({ "FocusLost", "FocusGained", "both" })

      if how == "both" then
        focus("FocusLost")
        focus("FocusGained")
      else
        focus(how)
      end

      return "focus: " .. how
    end,
  },
  resize = {
    2,
    function()
      vim.o.columns, vim.o.lines = 40 + random(180), 10 + random(60)
      focus("VimResized")

      return ("resize to %dx%d"):format(vim.o.columns, vim.o.lines)
    end,
  },
  insert = {
    6,
    function()
      if not vim.bo.modifiable then
        return nil
      end

      local keys = pick({ "i", "a", "o", "A", "O" }) .. pick(TEXT) .. "<Esc>"

      feed(keys)

      return "type " .. keys
    end,
  },
  normal = {
    6,
    function()
      local keys = pick(KEYS)

      feed(keys)

      return "keys " .. keys
    end,
  },
  write = {
    2,
    function()
      local buf = vim.api.nvim_get_current_buf()
      local name = vim.fs.basename(vim.api.nvim_buf_get_name(buf))

      if not (vim.bo[buf].buftype == "" and vim.bo[buf].modifiable and sample_file(buf) and SAMPLES[name]) then
        return nil
      end

      -- The sample as written first: random typing makes code a formatter rightly refuses, and that is no failure.
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, SAMPLES[name])
      vim.g.autoformat = true

      local ok, err = pcall(function()
        vim.cmd("write!")
      end)

      vim.g.autoformat = false
      if not ok then
        error(err, 0)
      end

      return "write " .. name
    end,
  },
  reload = {
    1,
    function()
      if not sample_file(0) then
        return nil
      end

      vim.cmd("edit!")

      return "edit!"
    end,
  },
  changed_on_disk = {
    1,
    function()
      -- Text a formatter takes as it is, when it is written later.
      local name = pick({ "plain.txt", "notes.md" })
      local path = vim.fs.joinpath(samples, name)
      local buf = vim.fn.bufnr(path)

      -- A buffer with changes of its own would ask which to keep.
      if buf ~= -1 and vim.bo[buf].modified then
        return nil
      end

      local lines = vim.fn.readfile(path)

      lines[#lines + 1] = "changed on disk " .. random(1000)
      vim.fn.writefile(lines, path)
      vim.cmd.checktime()

      return "changed " .. name .. " on disk, :checktime"
    end,
  },
  language_server = {
    2,
    function()
      local how, method = unpack(pick({
        { "hover", "textDocument/hover" },
        { "document_highlight", "textDocument/documentHighlight" },
        { "signature_help", "textDocument/signatureHelp" },
      }))

      -- Asking a server without the method is Neovim's own error, not the configuration's.
      if #vim.lsp.get_clients({ bufnr = 0, method = method }) == 0 then
        return nil
      end

      vim.lsp.buf[how]()

      return "lsp " .. how
    end,
  },
  colors = {
    1,
    function()
      if random(2) == 1 and vim.g.colors_name then
        vim.cmd.colorscheme(vim.g.colors_name)

        return "colorscheme " .. vim.g.colors_name
      end

      vim.o.background = vim.o.background == "dark" and "light" or "dark"

      return "background " .. vim.o.background
    end,
  },
  diagnostics = {
    1,
    function()
      vim.diagnostic.enable(not vim.diagnostic.is_enabled())

      return "diagnostics " .. tostring(vim.diagnostic.is_enabled())
    end,
  },
  terminal = {
    1,
    function()
      vim.cmd.terminal()
      settle(300)
      vim.cmd("bwipeout!")

      return "terminal, then wiped"
    end,
  },
  floats = {
    2,
    function()
      close_floats()

      return "close floating windows"
    end,
  },
  hold = {
    2,
    function()
      focus("CursorHold")

      return "CursorHold"
    end,
  },
  load = {
    1,
    function()
      local waiting = vim.tbl_filter(function(plugin)
        return not plugin._.loaded
      end, require("lazy").plugins())

      if #waiting == 0 then
        return nil
      end

      local plugin = pick(waiting)

      vim.cmd("Lazy! load " .. plugin.name)

      return "load " .. plugin.name
    end,
  },
  substitute = {
    1,
    function()
      if not vim.bo.modifiable then
        return nil
      end

      vim.cmd("silent %s/a/b/ge")

      return ":%s/a/b/ge"
    end,
  },
}

local weighted = {}

for _, name in ipairs(vim.tbl_keys(ACTIONS)) do
  for _ = 1, ACTIONS[name][1] do
    weighted[#weighted + 1] = name
  end
end

table.sort(weighted)

local function is_lua_error(text)
  return text:find("E5108", 1, true)
    or text:find("E5113", 1, true)
    or text:find("E5560", 1, true)
    or text:find("Error executing", 1, true)
    or text:find("stack traceback", 1, true)
    or text:find("%.lua:%d+:") ~= nil
end

local recent = {} -- the last steps, told with a failure
local reported = {} -- a message once, not once per step

local function fail_once(what, step)
  if reported[what] then
    return
  end

  reported[what] = true
  check(false, ("step %d: %s"):format(step, what))
  for _, line in ipairs(recent) do
    out("STEP " .. line)
  end
end

local held = 0

-- What the step left: Lua errors in messages, error notifications, input method switches with no UI.
local function after(step)
  local messages = vim.api.nvim_exec2("messages", { output = true }).output

  vim.cmd("messages clear")
  for line in vim.gsplit(messages, "\n", { plain = true, trimempty = true }) do
    if is_lua_error(line) then
      fail_once("a Lua error: " .. line, step)
    end
  end

  for _, note in ipairs(notes) do
    local text = note.msg:gsub("%s+", " ")

    -- "LSP[name] ..." is what a server itself says (window/showMessage): its own trouble, told, not counted. An
    -- error answer to a request the configuration made stays a failure.
    if note.level >= vim.log.levels.ERROR and text:find("^LSP%[[^%]]+%] ") then
      if not reported[text] then
        reported[text] = true
        out(("INFO step %d: a language server's own error message (its trouble, not counted): %s"):format(step, text))
      end
    elseif note.level >= vim.log.levels.ERROR then
      fail_once("an error notification: " .. text, step)
    end
  end

  notes = {}
  for i = held + 1, #recorder.held_back do
    fail_once("an input method switch with no UI attached: " .. recorder.held_back[i], step)
  end

  held = #recorder.held_back
  watch_notify()
end

out(("INFO %d samples in %s"):format(#names, samples))
vim.cmd.cd(vim.fn.fnameescape(samples))
after(0)

-- CONFIG_FUZZ_REPLAY: a file of actions as the DID lines tell them, one per line, run in order and nothing after;
-- to cut a failing run down to the steps the failure needs.
local replay = os.getenv("CONFIG_FUZZ_REPLAY")

if replay then
  local function run(name)
    return function()
      ACTIONS[name][2]()
    end
  end

  local REPLAY = {
    {
      "^edit (.+)$",
      function(name)
        vim.cmd.edit(vim.fn.fnameescape(name))
      end,
    },
    {
      "^new buffer, filetype (%S+)$",
      function(ft)
        vim.cmd.enew()
        vim.bo.filetype = ft
      end,
    },
    {
      "^close a window$",
      function()
        vim.cmd.close()
      end,
    },
    {
      "^focus: (%a+)$",
      function(how)
        for _, event in ipairs(how == "both" and { "FocusLost", "FocusGained" } or { how }) do
          focus(event)
        end
      end,
    },
    {
      "^resize to (%d+)x(%d+)$",
      function(columns, lines)
        vim.o.columns, vim.o.lines = tonumber(columns), tonumber(lines)
        focus("VimResized")
      end,
    },
    { "^type (.+)$", feed },
    { "^keys (.+)$", feed },
    { "^write ", run("write") },
    {
      "^changed (%S+) on disk, :checktime$",
      function(name)
        local path = vim.fs.joinpath(samples, name)

        vim.fn.writefile(vim.list_extend(vim.fn.readfile(path), { "changed on disk" }), path)
        vim.cmd.checktime()
      end,
    },
    {
      "^lsp (%S+)$",
      function(how)
        vim.lsp.buf[how]()
      end,
    },
    { "^colorscheme (.+)$", vim.cmd.colorscheme },
    {
      "^background (%a+)$",
      function(background)
        vim.o.background = background
      end,
    },
    {
      "^diagnostics (%a+)$",
      function(on)
        vim.diagnostic.enable(on == "true")
      end,
    },
    { "^terminal, then wiped$", run("terminal") },
    { "^close floating windows$", close_floats },
    {
      "^CursorHold$",
      function()
        focus("CursorHold")
      end,
    },
    {
      "^load (.+)$",
      function(name)
        vim.cmd("Lazy! load " .. name)
      end,
    },
    { "^:%%s/a/b/ge$", run("substitute") },
    { "^nothing$", function() end }, -- a step whose action did not apply: its wait still counts
    -- split, vsplit, tabnew, tabclose, bnext, bprevious, bdelete!, bwipeout!, edit!
    {
      "^(%S+)$",
      function(command)
        vim.cmd(command)
      end,
    },
  }

  for step, what in ipairs(vim.fn.readfile(replay)) do
    out(("TRY %d %s"):format(step, what))
    for _, entry in ipairs(REPLAY) do
      local captures = { what:match(entry[1]) }

      if captures[1] then
        local ok, err = pcall(entry[2], unpack(captures))

        if not ok and is_lua_error(tostring(err)) then
          fail_once(tostring(err), step)
        end

        break
      end
    end

    settle(step % 25 == 0 and 600 or 20)
    after(step)
  end

  out("DONE")
  report:close()
  vim.cmd("qall!")

  return
end

local vim_errors = 0

for step = 1, steps do
  local name = pick(weighted)

  -- Before the action: if Neovim crashes in it, this is the last line.
  out(("TRY %d %s"):format(step, name))

  local ok, what = pcall(ACTIONS[name][2])

  if not ok then
    what = ("%s: %s"):format(name, (tostring(what):gsub("%s+", " ")))
  end

  -- Every step, "nothing" included: the DID lines replay as they are (CONFIG_FUZZ_REPLAY), waits and all.
  out(("DID %d %s"):format(step, what or "nothing"))
  if what then
    table.insert(recent, ("%d %s"):format(step, what))
    if #recent > 6 then
      table.remove(recent, 1)
    end
  end

  if not ok then
    if is_lua_error(what) then
      fail_once(what, step)
    else
      vim_errors = vim_errors + 1
    end
  end

  settle(step % 25 == 0 and 600 or 20)
  after(step)
end

out(
  ("INFO %d actions ended in a Vim error of their own (E-numbers such as no string under the cursor)"):format(
    vim_errors
  )
)

-- Every plugin, then the same work four times: what grows each time leaks.
out("TRY load every plugin")
pcall(function()
  vim.cmd("Lazy! load all")
end)
settle(2000)
after(steps + 1)
close_floats()
vim.cmd("silent! only")
vim.cmd("silent! tabonly")

local CYCLE = { "main.c", "util.cpp", "start.S", "script.py", "notes.md", "module.lua", "data.json", "plain.txt" }

local function cycle()
  for _, name in ipairs(CYCLE) do
    out("TRY repeated work on " .. name)
    vim.cmd.edit(vim.fn.fnameescape(name))
    vim.cmd.split()
    vim.cmd.close()
    focus("FocusLost")
    focus("FocusGained")
    feed("ix<Esc>u")
    focus("VimResized")
    focus("CursorHold")
    settle(150)
  end

  close_floats()
  settle(2500)
end

local function snapshot()
  local s = {}

  local function add(what, n)
    s[what] = (s[what] or 0) + (n or 1)
  end

  for _, au in ipairs(vim.api.nvim_get_autocmds({})) do
    add(("autocmds %s %s"):format(au.group_name or "(no group)", au.event))
  end

  for _, mode in ipairs({ "n", "x", "s", "o", "i", "c", "t" }) do
    add("global mappings " .. mode, #vim.api.nvim_get_keymap(mode))
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      for _, mode in ipairs({ "n", "x", "i" }) do
        add("buffer mappings " .. mode, #vim.api.nvim_buf_get_keymap(buf, mode))
      end
    end
  end

  vim.uv.walk(function(handle)
    if not handle:is_closing() then
      add("libuv handles " .. handle:get_type())
    end
  end)

  add("language server clients", #vim.lsp.get_clients())
  add("buffers", #vim.api.nvim_list_bufs())
  add("windows", #vim.api.nvim_list_wins())
  add("namespaces", vim.tbl_count(vim.api.nvim_get_namespaces()))
  add("user commands", vim.tbl_count(vim.api.nvim_get_commands({})))

  return s
end

local shots = {}

for i = 1, 4 do
  local ok, err = pcall(cycle)

  if not ok then
    fail_once("the repeated work: " .. tostring(err), steps + 1 + i)
  end

  after(steps + 1 + i)
  shots[i] = snapshot()
end

local grows = {}

for what, n in pairs(shots[4]) do
  local n2, n3 = shots[2][what] or 0, shots[3][what] or 0

  if n2 < n3 and n3 < n then
    grows[#grows + 1] = ("%s: %d, %d, %d"):format(what, n2, n3, n)
  end
end

table.sort(grows)
for _, line in ipairs(grows) do
  check(false, "grows with each repetition of the same work: " .. line)
end

if #grows == 0 then
  check(true, "nothing grows with each repetition of the same work (autocmds, mappings, handles, clients, buffers)")
end

-- The mappings: one part of the configuration setting another's key, or a plugin setting the configuration's.
local conflicts, plugin_over, ours_over, theirs = {}, {}, 0, 0

for _, o in ipairs(recorder.overwrites) do
  local was_ours, is_ours = recorder.ours(o.before, o.before_defined), recorder.ours(o.after, o.after_defined)
  local line = ("%s %s (%s): %s, then %s%s"):format(
    o.mode,
    o.lhs,
    o.scope == "global" and "global" or "a buffer's own",
    o.before,
    o.after,
    o.after_defined and (" with a function of " .. o.after_defined) or ""
  )

  if was_ours and is_ours then
    conflicts[line] = true
  elseif was_ours then
    plugin_over[line] = true
  elseif is_ours then
    ours_over = ours_over + 1
  else
    theirs = theirs + 1
  end
end

for _, line in ipairs(vim.tbl_keys(conflicts)) do
  check(false, "two parts of the configuration set one key: " .. line)
end

for _, line in ipairs(vim.tbl_keys(plugin_over)) do
  check(false, "a plugin set a key the configuration had set: " .. line)
end

for _, line in ipairs(recorder.lost()) do
  check(false, "a mapping of the configuration replaced by Vimscript: " .. line)
end

check(
  next(conflicts) == nil and next(plugin_over) == nil and #recorder.lost() == 0,
  ("the mappings: %d recorded, %d of plugins' keys set by the configuration on purpose, %d between plugins"):format(
    vim.tbl_count(recorder.live),
    ours_over,
    theirs
  )
)

check(#recorder.held_back == 0, "no input method switch with no UI attached")
check(
  #recorder.faults == 0,
  "the recorder had no error of its own (a fault of this test, not of the configuration): "
    .. table.concat(vim.list_slice(recorder.faults, 1, 3), " | ")
)
out(("INFO %d random steps, seed %d"):format(steps, seed))

for _, client in ipairs(vim.lsp.get_clients()) do
  pcall(function()
    client:stop(true)
  end)
end

vim.wait(3000, function()
  return #vim.lsp.get_clients() == 0
end, 50)

pcall(function()
  require("persistence").stop()
end)

out("DONE")
report:close()
vim.cmd("qall!")
