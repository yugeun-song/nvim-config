-- Who sets and deletes each mapping, for tests/config_fuzz/: loaded before the configuration (--cmd), it wraps
-- vim.keymap.set/del and nvim_[buf_]set_keymap/del_keymap and keeps, per mode, lhs and scope, the file that set the
-- live mapping, and each time a mapping was set over another file's. It also holds back, and records, the commands
-- that switch the foreground window's input method while no UI is attached.
--   Installed once (installing again changes nothing); a call is recorded once (vim.keymap.set calls
--   nvim_set_keymap, which then only tells the rhs it was given); the caller is the first frame outside this file
--   and Neovim's keymap code; the wrapped function's results and errors pass through unchanged, the depth restored;
--   a failed call records nothing. A tail call (return vim.keymap.set(...)) leaves no frame: its caller is named.
-- Vimscript mappings (:nnoremap) bypass the wrappers: lost() finds those that replaced a recorded one.
local M = {}

local is_windows = vim.fn.has("win32") == 1
local repo -- the configuration's directory: "/" separators, lowercase on Windows
local depth = 0
local pending = {} -- the keys the outermost set call recorded, for the rhs the API call underneath is given
local installed = false

M.live = {} -- [key] = { file, line, mode, lhs, scope, rhs, defined }
---@type { mode: string, lhs: string, scope: string|integer, before: string, after: string, before_defined: string?, after_defined: string? }[]
M.overwrites = {}
M.held_back = {} -- command lines held back
M.calls = 0 -- recorded set and del calls
M.faults = {} -- the recorder's own errors: kept out of the call it watches, told by the test

local function slashed(path)
  path = (path or ""):gsub("\\", "/")

  return is_windows and path:lower() or path
end

local this_file = slashed((debug.getinfo(1, "S").source:gsub("^@", "")))

-- "cfg:<path in the configuration>", "<plugin>/<path>" for lazy.nvim's plugins, else the source as given.
local function label(source)
  local raw = source:gsub("^@", "")

  -- A chunk run by a relative name (nvim -l tests/...) tells it relative.
  if source:sub(1, 1) == "@" and not raw:find("^%a:[/\\]") and not raw:find("^[/\\]") then
    raw = vim.fn.fnamemodify(raw, ":p")
  end

  local path = slashed(raw)

  if repo and vim.startswith(path, repo .. "/") then
    return "cfg:" .. path:sub(#repo + 2)
  end

  return (path:gsub("^.*/lazy/", ""))
end

-- The first caller outside this file and Neovim's vim.keymap. lazy.nvim's key handler makes the mappings of the
-- specs' keys and keeps no file for them.
local function caller()
  for level = 3, 40 do
    local info = debug.getinfo(level, "Sl")

    if not info then
      break
    end

    local source = slashed(info.source)

    if source:find("/lazy/core/handler/keys%.lua$") then
      return "lazy.nvim keys", 0
    end

    local own = source:gsub("^@", "") == this_file
    local neovims = source == "@vim/keymap.lua" or source:find("/runtime/lua/vim/keymap%.lua$") ~= nil

    if info.what ~= "C" and info.what ~= "tail" and not own and not neovims then
      return label(info.source), info.currentline or 0
    end
  end

  return "?", 0
end

-- The modes a mode argument stands for, as :map's do.
local MODES = { [""] = { "n", "x", "s", "o" }, v = { "x", "s" }, ["!"] = { "i", "c" } }

function M.modes(mode)
  local out = {}

  for _, m in ipairs(type(mode) == "table" and mode or { mode }) do
    vim.list_extend(out, MODES[m] or { m })
  end

  return out
end

-- One spelling per key sequence: <leader> as mapleader stands now, <c-b> as <C-B>, "" as <Nop>.
function M.normalize(keys)
  if keys == "" then
    return "<Nop>"
  end

  local ok, raw = pcall(vim.keycode, keys)

  return ok and vim.fn.keytrans(raw) or keys
end

local function scope_of(buffer)
  if buffer == nil or buffer == false then
    return "global"
  end

  if buffer == true or buffer == 0 then
    return vim.api.nvim_get_current_buf()
  end

  return buffer
end

local function key_of(mode, lhs, scope)
  return mode .. " " .. lhs .. " " .. tostring(scope)
end

-- Where a function rhs was written: a plugin's helper (LazyVim's keys, Snacks.keymap) often sets the
-- configuration's own function, and the mapping is then the configuration's.
local function defined_in(rhs)
  local info = type(rhs) == "function" and debug.getinfo(rhs, "S")

  return info and info.what ~= "C" and ("%s:%d"):format(label(info.source), info.linedefined) or nil
end

-- What a set call would record, staged before the call (the caller is on the stack then) and kept by the returned
-- function once the call succeeded: a call that fails leaves nothing.
local function on_set(mode, lhs, rhs, buffer)
  local file, line = caller()
  local scope = scope_of(buffer)
  local norm = M.normalize(lhs)
  local defined = defined_in(rhs)

  pending = {}
  for _, m in ipairs(M.modes(mode)) do
    pending[#pending + 1] =
      { file = file, line = line, mode = m, lhs = norm, scope = scope, rhs = rhs, defined = defined }
  end

  local staged = pending

  return function()
    M.calls = M.calls + 1
    for _, entry in ipairs(staged) do
      local key = key_of(entry.mode, entry.lhs, entry.scope)
      local before = M.live[key]

      -- Another file setting the same rhs again replaces nothing.
      if before and before.file ~= entry.file and not rawequal(before.rhs, entry.rhs) then
        M.overwrites[#M.overwrites + 1] = {
          mode = entry.mode,
          lhs = entry.lhs,
          scope = entry.scope,
          before = before.file .. ":" .. before.line,
          after = entry.file .. ":" .. entry.line,
          before_defined = before.defined,
          after_defined = entry.defined,
        }
      end

      M.live[key] = entry
    end
  end
end

-- The rhs the API call underneath vim.keymap.set was given (a callback it wrapped, for an expr mapping).
local function on_api_set(rhs)
  for _, entry in ipairs(pending) do
    entry.rhs = rhs
  end
end

local function on_del(mode, lhs, buffer)
  local scope = scope_of(buffer)
  local norm = M.normalize(lhs)
  local modes = M.modes(mode)

  return function()
    M.calls = M.calls + 1
    for _, m in ipairs(modes) do
      M.live[key_of(m, norm, scope)] = nil
    end
  end
end

local function pack(...)
  return { n = select("#", ...), ... }
end

-- f(...) for the recorder's own work: an error of its own goes to M.faults, never into the call it watches.
local function quietly(f, ...)
  local ok, result = pcall(f, ...)

  if ok then
    return result
  end

  M.faults[#M.faults + 1] = tostring(result)
end

-- fn, with outer(...) staging what a call from outside records (kept once fn succeeded), and inner(...) told of a
-- call made from within another wrapped one.
local function wrap(fn, outer, inner)
  return function(...)
    local keep

    if depth == 0 then
      keep = quietly(outer, ...)
    elseif inner then
      quietly(inner, ...)
    end

    depth = depth + 1
    local result = pack(pcall(fn, ...))

    depth = depth - 1

    if not result[1] then
      error(result[2], 0)
    end

    if keep then
      quietly(keep)
    end

    return unpack(result, 2, result.n)
  end
end

function M.depth()
  return depth
end

-- The configuration's commands for English, as the driver hands them over once (know_switch_commands). The wrapper
-- only compares: calling into the configuration from inside vim.system() would run its code (a helper build,
-- lookups) on every command started, and could call vim.system() again.
local switch_commands = {}

function M.know_switch_commands(list)
  switch_commands = vim.deepcopy(list or {})
end

-- Those, and windows_ime_helper's commands that act on the foreground window.
local function switches_input_method(cmd)
  if type(cmd) ~= "table" or type(cmd[1]) ~= "string" then
    return false
  end

  if vim.fs.basename(slashed(cmd[1])):find("^windows_ime_helper") then
    return cmd[2] == "ime-english" or cmd[2] == "raise-window"
  end

  for _, command in ipairs(switch_commands) do
    if vim.deep_equal(command, cmd) then
      return true
    end
  end

  return false
end

function M.holds_back(cmd)
  return #vim.api.nvim_list_uis() == 0 and switches_input_method(cmd)
end

-- For the wrappers: in a libuv callback the API (nvim_list_uis) cannot be called, and the command passes as it is;
-- an error of the check is the recorder's, not the caller's.
local function hold(cmd)
  if vim.in_fast_event() or not quietly(M.holds_back, cmd) then
    return false
  end

  M.held_back[#M.held_back + 1] = quietly(table.concat, cmd, " ") or "?"

  return true
end

-- What vim.system() returns, for a command held back: done, with nothing said.
local function finished(on_exit)
  local result = { code = 0, signal = 0, stdout = "", stderr = "" }

  if on_exit then
    vim.schedule(function()
      on_exit(result)
    end)
  end

  return {
    pid = 0,
    wait = function()
      return result
    end,
    kill = function() end,
    write = function() end,
    is_closing = function()
      return true
    end,
  }
end

function M.install(configuration_dir)
  if configuration_dir then
    repo = slashed(vim.fs.normalize(configuration_dir))
  end

  if installed then
    return
  end

  installed = true

  vim.keymap.set = wrap(vim.keymap.set, function(mode, lhs, rhs, opts)
    return on_set(mode, lhs, rhs, opts and opts.buffer)
  end)

  vim.keymap.del = wrap(vim.keymap.del, function(mode, lhs, opts)
    return on_del(mode, lhs, opts and opts.buffer)
  end)

  vim.api.nvim_set_keymap = wrap(vim.api.nvim_set_keymap, function(mode, lhs, rhs, opts)
    return on_set(mode, lhs, opts and opts.callback or rhs, nil)
  end, function(_, _, rhs, opts)
    on_api_set(opts and opts.callback or rhs)
  end)

  vim.api.nvim_buf_set_keymap = wrap(vim.api.nvim_buf_set_keymap, function(buf, mode, lhs, rhs, opts)
    return on_set(mode, lhs, opts and opts.callback or rhs, buf)
  end, function(_, _, _, rhs, opts)
    on_api_set(opts and opts.callback or rhs)
  end)

  vim.api.nvim_del_keymap = wrap(vim.api.nvim_del_keymap, function(mode, lhs)
    return on_del(mode, lhs, nil)
  end)

  vim.api.nvim_buf_del_keymap = wrap(vim.api.nvim_buf_del_keymap, function(buf, mode, lhs)
    return on_del(mode, lhs, buf)
  end)

  local system = vim.system

  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd, opts, on_exit)
    if hold(cmd) then
      return finished(type(opts) == "function" and opts or on_exit)
    end

    return system(cmd, opts, on_exit)
  end

  local jobstart = vim.fn.jobstart

  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.jobstart = function(cmd, ...)
    if hold(cmd) then
      return 0
    end

    return jobstart(cmd, ...)
  end

  -- A buffer's own mappings go with it: set again once it is read again, they replace nothing.
  vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
    group = vim.api.nvim_create_augroup("config_fuzz_recorder", { clear = true }),
    callback = function(ev)
      for key, entry in pairs(M.live) do
        if entry.scope == ev.buf then
          M.live[key] = nil
        end
      end
    end,
  })
end

function M.is_configuration(file)
  return vim.startswith(file, "cfg:")
end

-- Whether one side of an overwrite is the configuration's: it made the call, or it wrote the function.
function M.ours(file, defined)
  return M.is_configuration(file) or (defined ~= nil and M.is_configuration(defined))
end

-- The configuration's recorded mappings that are no longer what it set, nor deleted through the wrappers: replaced
-- by something unrecorded (Vimscript's :map).
function M.lost()
  local now = {} -- [mode .. scope] = { [normalized lhs] = mapping }

  local function current(entry)
    local index = entry.mode .. " " .. tostring(entry.scope)

    if not now[index] then
      now[index] = {}

      local list = entry.scope == "global" and vim.api.nvim_get_keymap(entry.mode)
        or vim.api.nvim_buf_get_keymap(entry.scope, entry.mode)

      for _, mapping in ipairs(list) do
        now[index][M.normalize(mapping.lhs)] = mapping
      end
    end

    return now[index][entry.lhs]
  end

  local out = {}

  for _, entry in pairs(M.live) do
    local valid = entry.scope == "global" or vim.api.nvim_buf_is_valid(entry.scope)

    if valid and M.is_configuration(entry.file) then
      local mapping = current(entry)
      local same = mapping ~= nil
        and (
          type(entry.rhs) == "function" and mapping.callback == entry.rhs
          or type(entry.rhs) == "string" and M.normalize(mapping.rhs or "") == M.normalize(entry.rhs)
        )

      if not same then
        out[#out + 1] = ("%s %s (%s) of %s:%d"):format(
          entry.mode,
          entry.lhs,
          entry.scope == "global" and "global" or "buffer",
          entry.file,
          entry.line
        )
      end
    end
  end

  table.sort(out)

  return out
end

return M
