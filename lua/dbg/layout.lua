local ui = require("dbg.ui")
local panel = require("dbg.panel")

local M = {}

M.preset = "auto"

-- The only resolution that counts here is the terminal's cell grid, which is
-- exactly what `columns` and `lines` report.  Changing the font size in the
-- terminal emulator changes them, so every threshold below is expressed in
-- cells and re-measured on every resize.
-- The register rows carry a `<symbol + offset>` annotation, and on a kernel
-- those names are long; a narrow column cuts them off exactly where they start
-- being useful.
M.sidebar_min = 44
M.sidebar_max = 110
M.sidebar_share = 0.38
M.min_editor_width = 84
M.min_lines = 20
-- A register panel is only useful when the whole general set fits; a second
-- panel is worth stacking only once that is satisfied and there are rows left
-- over for it.
M.primary_rows = 28
M.extra_rows = 14

-- `weight` is how much of the side column a panel gets when several are
-- stacked.  Registers is the one you read continuously and it has the most
-- rows, so it takes the largest share and the rest sit below it.
local PANELS = {
  { name = "registers", title = "Registers", mod = "dbg.registers", weight = 5 },
  { name = "watch", title = "Watch", mod = "dbg.watch", weight = 4 },
  { name = "memory", title = "Memory", mod = "dbg.memory", weight = 3 },
  { name = "mappings", title = "Mappings", mod = "dbg.mappings", weight = 2 },
  { name = "session", title = "Target", mod = "dbg.session", weight = 2 },
}
local MIN_PANEL_ROWS = 5

local index = 1

local function slot(i)
  return "sidebar" .. i
end

local function panel_by_name(name)
  for i, p in ipairs(PANELS) do
    if p.name == name then
      return p, i
    end
  end
  return nil, nil
end

local function refresh(p)
  local ok, mod = pcall(require, p.mod)
  if not ok then
    return
  end
  if mod.probe then
    mod.probe()
  elseif mod.render then
    mod.render()
  end
end

local function live_slots()
  local set, list = {}, {}
  for i = 1, #PANELS do
    local win = panel.win(slot(i))
    if win then
      set[win] = true
      list[#list + 1] = win
    end
  end
  return set, list
end

function M.sidebar_size()
  local want = math.floor(vim.o.columns * M.sidebar_share)
  return math.max(M.sidebar_min, math.min(M.sidebar_max, want))
end

function M.wide()
  if M.preset == "wide" then
    return true
  end
  if M.preset == "compact" then
    return false
  end
  return vim.o.columns - M.sidebar_size() >= M.min_editor_width and vim.o.lines >= M.min_lines
end

-- Rows the side column actually gets: the grid minus the bottom panel, the
-- status line and the tab line.  Measured from the live windows when they are
-- up, estimated from the cell grid otherwise.
local function column_rows()
  local win = panel.win(slot(1))
  if win and vim.api.nvim_win_is_valid(win) then
    local total = 0
    local _, list = live_slots()
    for _, w in ipairs(list) do
      total = total + vim.api.nvim_win_get_height(w)
    end
    if total > 0 then
      return total
    end
  end
  return math.max(0, math.floor(vim.o.lines * 0.66) - 2)
end

-- How many panels the side column stacks: whatever the cell grid can carry
-- without squeezing the source window or cutting the first panel short, capped
-- by M.side_max.  The cap is 1 by request: the side column is for one panel at
-- full height, and everything else lives in the bottom bar.  ]p / [p still
-- cycle which panel occupies the column.
M.side_max = 1

function M.slots()
  if not M.wide() then
    return 0
  end
  local rows = column_rows()
  local by_height = 1 + math.floor((rows - M.primary_rows) / M.extra_rows)
  local by_width = math.floor((vim.o.columns - M.min_editor_width) / M.sidebar_min)
  return math.max(1, math.min(#PANELS, M.side_max, by_height, by_width))
end

function M.describe()
  local n = M.slots()
  return ("%dx%d cells, %s, %d side panel%s"):format(
    vim.o.columns,
    vim.o.lines,
    M.wide() and "wide" or "compact",
    n,
    n == 1 and "" or "s"
  )
end

local function shown_outside(p, own)
  local ok, mod = pcall(require, p.mod)
  if not ok then
    return true
  end
  for _, win in ipairs(vim.fn.win_findbuf(mod.buffer())) do
    if vim.api.nvim_win_is_valid(win) and not own[win] then
      return true
    end
  end
  return false
end

-- Walk the panel ring from the current position and take the first `count`
-- panels that no other window is already showing.
local function selection(count)
  local own = live_slots()
  local out, taken = {}, {}
  local i = index
  for _ = 1, #PANELS * 2 do
    if #out >= count then
      break
    end
    local p = PANELS[((i - 1) % #PANELS) + 1]
    if not taken[p.name] and not shown_outside(p, own) then
      taken[p.name] = true
      out[#out + 1] = p
    end
    i = i + 1
  end
  return out
end

local function bind_keys(buf)
  if vim.b[buf].dbg_panel_keys then
    return
  end
  vim.b[buf].dbg_panel_keys = true
  vim.keymap.set("n", "]p", function()
    M.sidebar_cycle(1)
  end, { buffer = buf, nowait = true, desc = "Debug panel: next" })
  vim.keymap.set("n", "[p", function()
    M.sidebar_cycle(-1)
  end, { buffer = buf, nowait = true, desc = "Debug panel: previous" })
end

local shown = {}

local function distribute()
  local _, list = live_slots()
  if #list < 2 then
    return
  end
  local total, weights, sum = 0, {}, 0
  for i, win in ipairs(list) do
    total = total + vim.api.nvim_win_get_height(win)
    local p = shown[i]
    weights[i] = (p and p.weight) or 1
    sum = sum + weights[i]
  end
  local used = 0
  for i = 1, #list - 1 do
    local rows = math.max(MIN_PANEL_ROWS, math.floor(total * weights[i] / sum))
    rows = math.min(rows, total - used - MIN_PANEL_ROWS * (#list - i))
    if rows < MIN_PANEL_ROWS then
      rows = MIN_PANEL_ROWS
    end
    pcall(vim.api.nvim_win_set_height, list[i], rows)
    used = used + rows
  end
end

function M.sidebar_close()
  for i = 1, #PANELS do
    local win = panel.win(slot(i))
    if win and #vim.api.nvim_list_wins() > 1 then
      pcall(vim.api.nvim_win_close, win, true)
    end
    panel.set_win(slot(i), nil)
  end
end

local opening = false

function M.sidebar_open()
  -- Opening the column moves buffers into windows, which fires the very
  -- autocmds that ask for the column to be rebuilt; without this guard the two
  -- feed each other forever.
  if opening then
    return
  end
  opening = true
  local ok, err = pcall(M.sidebar_open_unguarded)
  opening = false
  if not ok then
    error(err)
  end
end

function M.sidebar_open_unguarded()
  local count = M.slots()
  if count == 0 then
    M.sidebar_close()
    return
  end
  local chosen = selection(count)
  if #chosen == 0 then
    M.sidebar_close()
    return
  end

  local prev = vim.api.nvim_get_current_win()
  if not panel.win(slot(1)) then
    vim.cmd("topleft vertical " .. M.sidebar_size() .. "vsplit")
    vim.cmd("wincmd L")
    panel.set_win(slot(1), vim.api.nvim_get_current_win())
  end
  for i = 2, #chosen do
    if not panel.win(slot(i)) then
      local above = panel.win(slot(i - 1))
      if not above then
        break
      end
      vim.api.nvim_set_current_win(above)
      vim.cmd("belowright split")
      panel.set_win(slot(i), vim.api.nvim_get_current_win())
    end
  end
  for i = #chosen + 1, #PANELS do
    local win = panel.win(slot(i))
    if win then
      pcall(vim.api.nvim_win_close, win, true)
    end
    panel.set_win(slot(i), nil)
  end

  shown = {}
  for i, p in ipairs(chosen) do
    local win = panel.win(slot(i))
    if win then
      shown[i] = p
      local buf = require(p.mod).buffer()
      pcall(vim.api.nvim_win_set_buf, win, buf)
      vim.w[win].dbg_owned = "sidebar"
      ui.style_window(win, p.title .. (i == 1 and "   ]p / [p to switch" or ""))
      vim.wo[win].winfixwidth = true
      bind_keys(buf)
      refresh(p)
    end
  end
  distribute()
  -- dap-view resizes its own window when a new one appears, which reflows the
  -- column; settle the shares again once that has happened.
  vim.schedule(M.resize)
  if vim.api.nvim_win_is_valid(prev) then
    pcall(vim.api.nvim_set_current_win, prev)
  end
end

-- Without a line table there is no source line to point at, so the nearest
-- thing to "the code window follows the program counter" is the disassembly.
-- The console is left alone when it is the visible section: you are typing in
-- it, and gdb's own answer is already echoed there.
function M.show_disassembly()
  local ok, state = pcall(require, "dap-view.state")
  if not ok then
    return
  end
  local current = state.current_section
  if current == "repl" or current == "console" or current == "disassembly" then
    return
  end
  pcall(function()
    require("dap-view").show_view("disassembly")
  end)
end

function M.sidebar_toggle()
  if panel.win(slot(1)) then
    M.sidebar_close()
  else
    M.sidebar_open()
  end
end

function M.sidebar_cycle(delta)
  index = ((index - 1 + (delta or 1)) % #PANELS) + 1
  M.sidebar_open()
end

-- Called when a panel turns up in a window the sidebar does not own; the
-- sidebar rebuilds itself around whatever is still free.
function M.sidebar_next_free()
  M.sidebar_open()
end

function M.focus(name)
  local p, idx = panel_by_name(name)
  if not p then
    return
  end
  local _, list = live_slots()
  for _, win in ipairs(list) do
    if vim.api.nvim_win_get_buf(win) == require(p.mod).buffer() then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
  if #list > 0 then
    index = idx
    M.sidebar_open()
    local win = panel.win(slot(1))
    if win then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
  local ok = pcall(function()
    require("dap-view").jump_to_view(name)
  end)
  if not ok then
    require(p.mod).open()
  end
end

function M.pick()
  vim.ui.select(PANELS, {
    prompt = "Show panel",
    format_item = function(p)
      return p.title
    end,
  }, function(p)
    if p then
      M.focus(p.name)
    end
  end)
end

function M.apply()
  if M.wide() then
    M.sidebar_open()
  else
    M.sidebar_close()
  end
  M.fit()
end

-- Re-measure against the current cell grid: side column width, the stacked
-- heights, the winbar labels, and each visible panel, whose own column maths
-- (bytes per row, register grid) is recomputed as it renders.
-- Sizing only: cheap enough to run whenever a window appears or the target
-- stops, which is when dap-view reflows the column out from under us.
function M.resize()
  local win = panel.win(slot(1))
  if win then
    pcall(vim.api.nvim_win_set_width, win, M.sidebar_size())
  end
  distribute()
  pcall(function()
    require("dap-view.options.winbar").refresh_winbar()
  end)
end

function M.fit()
  M.resize()
  if not require("dap").session() then
    return
  end
  for _, p in ipairs(PANELS) do
    local ok, mod = pcall(require, p.mod)
    if ok and #vim.fn.win_findbuf(mod.buffer()) > 0 then
      refresh(p)
    end
  end
end

function M.refresh_sidebar()
  local _, list = live_slots()
  for _, win in ipairs(list) do
    local buf = vim.api.nvim_win_get_buf(win)
    for _, p in ipairs(PANELS) do
      local ok, mod = pcall(require, p.mod)
      if ok and mod.buffer() == buf then
        refresh(p)
      end
    end
  end
end

local restore = nil

local function is_debug_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local ft = vim.bo[buf].filetype
  return ft:match("^dbg%-") ~= nil
    or ft:match("^dap%-view") ~= nil
    or ft == "dap-repl"
    or ft == "dap-disassembly"
    or ft == "dapui_console"
end

local function debug_windows()
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_debug_buf(vim.api.nvim_win_get_buf(win)) then
      out[#out + 1] = win
    end
  end
  return out
end

-- Remember the window layout the user had before the debugger took over, so
-- that ending a session can put it back the way an IDE does.
function M.snapshot()
  if restore then
    return
  end
  local kept = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not is_debug_buf(vim.api.nvim_win_get_buf(win)) then
      kept = kept + 1
    end
  end
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local listed = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted then
      listed[b] = true
    end
  end
  restore = {
    tab = vim.api.nvim_get_current_tabpage(),
    sizes = vim.fn.winrestcmd(),
    count = kept,
    win = win,
    buf = not is_debug_buf(buf) and buf or nil,
    listed = listed,
  }
end

-- The debugger lists whatever source it jumped into, which is how a glibc
-- header ends up in the tabline.  Anything it brought in that the user has not
-- touched goes away with the session.
local function drop_borrowed(listed)
  if not listed then
    return
  end
  local candidates, survivors = {}, 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
      local borrowed = not listed[buf]
        and not vim.bo[buf].modified
        and vim.bo[buf].buftype == ""
        and #vim.fn.win_findbuf(buf) == 0
      if borrowed then
        candidates[#candidates + 1] = buf
      else
        survivors = survivors + 1
      end
    end
  end
  for _, buf in ipairs(candidates) do
    if survivors == 0 and buf == candidates[#candidates] then
      break
    end
    pcall(vim.api.nvim_buf_delete, buf, { force = false })
  end
end

-- Where the debugger is allowed to show source.  nvim-dap otherwise falls back
-- to "the window before this one", which is a debugger panel when you step from
-- the console, and dap-view pins its panel with 'winfixbuf', so the jump throws
-- E1513 from inside nvim-dap's coroutine and takes the step with it.
function M.source_window()
  local function usable(win)
    if not (win and vim.api.nvim_win_is_valid(win)) then
      return false
    end
    local ok, fixed = pcall(function()
      return vim.wo[win].winfixbuf
    end)
    if ok and fixed then
      return false
    end
    local buf = vim.api.nvim_win_get_buf(win)
    return not is_debug_buf(buf) and vim.bo[buf].buftype == ""
  end
  if restore and usable(restore.win) then
    return restore.win
  end
  local current = vim.api.nvim_get_current_win()
  if usable(current) then
    return current
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if usable(win) then
      return win
    end
  end
  -- Starting a session straight from the start screen leaves no window holding a
  -- file, so the search above finds nothing and the source ends up in a new split
  -- with the start screen still occupying the editor area.  A start screen is the
  -- editor area, it just has no file in it yet, so take it over.
  local START = {
    snacks_dashboard = true,
    alpha = true,
    dashboard = true,
    starter = true,
    ministarter = true,
    startify = true,
  }
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
      local ok, fixed = pcall(function()
        return vim.wo[win].winfixbuf
      end)
      local buf = vim.api.nvim_win_get_buf(win)
      if not (ok and fixed) and not is_debug_buf(buf) and START[vim.bo[buf].filetype] then
        return win
      end
    end
  end
  return nil
end

function M.jump(bufnr, line, column)
  local win = M.source_window()
  if not win then
    local prev = vim.api.nvim_get_current_win()
    vim.cmd("topleft split")
    win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_is_valid(prev) then
      pcall(vim.api.nvim_set_current_win, prev)
    end
  end
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  pcall(vim.api.nvim_win_set_buf, win, bufnr)
  pcall(vim.api.nvim_win_set_cursor, win, { line, math.max(0, (column or 1) - 1) })
  pcall(vim.api.nvim_win_call, win, function()
    vim.cmd("normal! zz")
  end)
end

function M.enter()
  -- Every session starts with Registers on the right; the ring position only
  -- moves when you cycle it with ]p / [p.
  index = 1
  M.snapshot()
  M.apply()
end

-- Close everything the debugger opened and restore the saved layout.
function M.leave()
  M.sidebar_close()
  pcall(function()
    require("dap-view").close()
  end)
  pcall(function()
    -- "toggle" closes the window but keeps the buffer; a plain close deletes it
    -- and the console history with it.
    require("dap").repl.close({ mode = "toggle" })
  end)
  for _, win in ipairs(debug_windows()) do
    if vim.api.nvim_win_is_valid(win) and #vim.api.nvim_list_wins() > 1 then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  local saved = restore
  restore = nil
  if not saved then
    return
  end
  if saved.tab == vim.api.nvim_get_current_tabpage() then
    if #vim.api.nvim_list_wins() == saved.count then
      pcall(vim.cmd, saved.sizes)
    end
    if saved.win and vim.api.nvim_win_is_valid(saved.win) then
      pcall(vim.api.nvim_set_current_win, saved.win)
      if saved.buf and vim.api.nvim_buf_is_valid(saved.buf) then
        pcall(vim.api.nvim_win_set_buf, saved.win, saved.buf)
      end
    end
  end
  drop_borrowed(saved.listed)
end

return M
