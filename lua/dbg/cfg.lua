local panel = require("dbg.panel")
local gdbq = require("dbg.gdbq")
local ui = require("dbg.ui")

local M = {}

-- The control-flow view.  Structure comes from `cfgjson`, which disassembles
-- whatever address space is live and so works before the MMU is on.  Whether the
-- branch under the program counter is taken is decided here, by the evaluator
-- the disassembly panel already uses.
--
-- Only the branch at the program counter has a decided state; every other one is
-- drawn muted, because the registers that would settle it do not yet hold the
-- values they will when control arrives.

-- The graph is the whole view: the listing it used to offer is the disassembly
-- panel's job, and that panel now draws the same branch lanes.
local state = { data = nil, error = nil, generation = 0, mode = "graph", detail = 2, boxes = {} }

local MNEM_WIDTH = 8

function M.buffer()
  local buf, created = panel.buffer("cfg")
  if created then
    -- Listed so the tabline carries it like any other file.  A winbar label
    -- would cost a row and duplicate what the tabline already says.
    vim.bo[buf].buflisted = true
    pcall(vim.api.nvim_buf_set_name, buf, "control-flow")
    vim.keymap.set("n", "r", function()
      M.probe()
    end, { buffer = buf, nowait = true, desc = "Control flow: refresh" })
    vim.keymap.set("n", "p", function()
      M.goto_pc()
    end, { buffer = buf, nowait = true, desc = "Control flow: back to the program counter" })
    vim.keymap.set("n", "<CR>", function()
      M.open_source()
    end, { buffer = buf, nowait = true, desc = "Control flow: open this instruction's source line" })
    for key, delta in pairs({ ["+"] = 1, ["="] = 1, ["-"] = -1, ["_"] = -1 }) do
      vim.keymap.set("n", key, function()
        M.zoom(delta)
      end, { buffer = buf, nowait = true, desc = "Control flow: more/less detail" })
    end
    -- Block-wise motion on the capitals; h j k l stay ordinary cursor keys,
    -- because a graph this size is still read by scrolling most of the time.
    for key, dir in pairs({ H = "left", L = "right", J = "down", K = "up" }) do
      vim.keymap.set("n", key, function()
        M.move(dir)
      end, { buffer = buf, nowait = true, desc = "Control flow: next block " .. dir })
    end
  end
  return buf
end

-- Kept so anything still calling it does not error; the control-flow view is
-- the graph, and the listing lives in the disassembly panel.
-- Detail, not scale: see cfgbox.  Redraw rather than reflow, because box widths
-- change with the level.
function M.zoom(delta)
  local box = require("dbg.cfgbox")
  local want = math.max(0, math.min(box.DETAIL_MAX, (state.detail or 2) + delta))
  if want == state.detail then
    return
  end
  state.detail = want
  M.render()
  local names = { "labels only", "no addresses", "full" }
  require("dbg.notify").info("Control flow: " .. names[want + 1])
end

local function cursor_block()
  -- panel.buffer returns (buf, created); passing the call straight in hands
  -- bufwinid two arguments.
  local buf = panel.buffer("cfg")
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return nil, nil
  end
  local pos = vim.api.nvim_win_get_cursor(win)
  local best, bestd = nil, nil
  for id, b in pairs(state.boxes or {}) do
    if pos[1] >= b.row and pos[1] < b.row + b.height then
      return id, win
    end
    local d = math.abs(pos[1] - b.row)
    if not bestd or d < bestd then
      best, bestd = id, d
    end
  end
  return best, win
end

-- Move to the nearest block in a direction, measured between box centres.  A
-- graph is two-dimensional, so line-wise motion is the wrong unit for it.
function M.move(dir)
  local from, win = cursor_block()
  local boxes = state.boxes or {}
  if not win or not from or not boxes[from] then
    return
  end
  local a = boxes[from]
  local ar, ac = a.row + a.height / 2, a.col + a.width / 2
  local best, bestd
  for id, b in pairs(boxes) do
    if id ~= from then
      local br, bc = b.row + b.height / 2, b.col + b.width / 2
      local ok = (dir == "down" and br > ar)
        or (dir == "up" and br < ar)
        or (dir == "right" and bc > ac)
        or (dir == "left" and bc < ac)
      if ok then
        -- distance along the direction dominates, so a block far off to the side
        -- does not win over one directly below.
        local along = (dir == "down" or dir == "up") and math.abs(br - ar) or math.abs(bc - ac)
        local across = (dir == "down" or dir == "up") and math.abs(bc - ac) or math.abs(br - ar)
        local d = along + across * 3
        if not bestd or d < bestd then
          best, bestd = id, d
        end
      end
    end
  end
  if not best then
    return
  end
  local t = boxes[best]
  pcall(vim.api.nvim_win_set_cursor, win, { t.row, math.max(0, t.col - 1) })
  pcall(vim.api.nvim_win_call, win, function()
    vim.cmd("normal! zz")
  end)
end

function M.toggle_mode()
  require("dbg.notify").info("Control flow is the graph; the listing is the disassembly panel.")
end

-- The row the cursor is on, as an index into the payload's instruction list.
local function row_under_cursor()
  local buf = panel.buffer("cfg")
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      local lnum = vim.api.nvim_win_get_cursor(win)[1]
      local first = state.first_insn_line
      if first and lnum >= first then
        return lnum - first + 1
      end
    end
  end
  return nil
end

function M.goto_pc()
  local data = state.data
  if not (data and data.pc_row and state.first_insn_line) then
    return
  end
  local buf = panel.buffer("cfg")
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_set_cursor, win, { state.first_insn_line + data.pc_row, 1 })
    end
  end
end

function M.open_source()
  local data = state.data
  local idx = row_under_cursor()
  local insn = data and idx and data.insns and data.insns[idx]
  if not (insn and insn.file and insn.line) then
    require("dbg.notify").warn("No source line is recorded for this instruction.")
    return
  end
  local bufnr = vim.fn.bufadd(insn.file)
  vim.fn.bufload(bufnr)
  require("dbg.layout").jump(bufnr, insn.line, 1)
end

-- Whether the branch on the program counter's row will be taken.  Returns the
-- highlight group to paint its arrow with; nil when the row holds no branch.
local function pc_branch_group(data)
  if not data.pc_row then
    return nil
  end
  local insn = data.insns[data.pc_row + 1]
  if not insn then
    return nil
  end
  local ok, disasm = pcall(require, "dbg.disasm")
  if not ok then
    return nil
  end
  local values = {}
  local okr, registers = pcall(require, "dbg.registers")
  if okr then
    values = registers.values() or {}
  end
  local line = ("%s: %s %s"):format(insn.addr, insn.mnemonic, insn.operands or "")
  local target, taken = disasm.branch_at(line, values)
  if not target then
    return nil
  end
  if taken == true then
    return "DbgBranchTaken"
  elseif taken == false then
    return "DbgBranchNotTaken"
  end
  return "DbgBranchUnknown"
end

-- The payload crosses a channel, so it is data from outside no matter who wrote
-- the other end.  Shapes are forced here, once, instead of every reader
-- rediscovering that a field it expected is a number or missing.
local function finite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function as_int(v, fallback)
  if finite(v) then
    return math.floor(v)
  end
  if type(v) == "string" then
    local n = tonumber(v)
    if finite(n) then
      return math.floor(n)
    end
  end
  return fallback
end

local function as_str(v, fallback)
  if type(v) == "string" then
    return v
  end
  if type(v) == "number" and v == v then
    return tostring(v)
  end
  return fallback
end

local MAX_TEXT = 400

local function clamp_text(v, fallback)
  local out = as_str(v, fallback)
  if #out > MAX_TEXT then
    out = out:sub(1, MAX_TEXT) .. "~"
  end
  return out
end

local function normalize(data)
  if type(data) ~= "table" then
    return nil
  end
  local out = {
    arch = as_str(data.arch, nil),
    inlined_at = as_str(data.inlined_at, nil),
    pc = as_str(data.pc, nil),
    gutter_width = math.max(0, as_int(data.gutter_width, 0)),
    line_info = type(data.line_info) == "table" and data.line_info or {},
    insns = {},
    blocks = {},
    block_edges = {},
    edges = {},
  }
  out.line_info = {
    missing = as_int(out.line_info.missing, 0),
    total = as_int(out.line_info.total, 0),
    why = as_str(out.line_info.why, nil),
  }
  local fn = type(data.function_) == "table" and data.function_ or {}
  out.function_ = {
    name = clamp_text(fn.name, "?"),
    lo = clamp_text(fn.lo, "?"),
    hi = clamp_text(fn.hi, "?"),
    bounded_by = as_str(fn.bounded_by, nil),
    source = as_str(fn.source, nil),
  }

  if type(data.insns) == "table" then
    for _, raw in ipairs(data.insns) do
      if type(raw) == "table" then
        out.insns[#out.insns + 1] = {
          addr = clamp_text(raw.addr, "?"),
          mnemonic = clamp_text(raw.mnemonic, ""),
          operands = clamp_text(raw.operands, ""),
          gutter = clamp_text(raw.gutter, ""),
          is_pc = raw.is_pc == true,
          terminator = as_str(raw.terminator, nil),
          file = type(raw.file) == "string" and raw.file or nil,
          line = as_int(raw.line, nil),
        }
      end
    end
  end
  local ninsn = #out.insns

  if type(data.blocks) == "table" then
    for _, raw in ipairs(data.blocks) do
      if type(raw) == "table" then
        local first = as_int(raw.first, nil)
        local last = as_int(raw.last, nil)
        -- A block whose rows are not inside the listing describes something that
        -- is not here; drawing it would invent instructions.
        if first and last and first >= 0 and last >= first and last < ninsn then
          out.blocks[#out.blocks + 1] = {
            id = as_int(raw.id, #out.blocks),
            first = first,
            last = last,
            start = clamp_text(raw.start, "?"),
            ["end"] = clamp_text(raw["end"], "?"),
            rank = math.max(0, as_int(raw.rank, 0)),
            order = math.max(0, as_int(raw.order, 0)),
            state = as_str(raw.state, "unknown"),
            terminator = as_str(raw.terminator, nil),
          }
        end
      end
    end
  end
  local byid = {}
  for _, b in ipairs(out.blocks) do
    byid[b.id] = true
  end

  if type(data.block_edges) == "table" then
    for _, raw in ipairs(data.block_edges) do
      if type(raw) == "table" then
        local from, to = as_int(raw.from, nil), as_int(raw.to, nil)
        if from and to and byid[from] and byid[to] then
          out.block_edges[#out.block_edges + 1] = {
            from = from,
            to = to,
            kind = as_str(raw.kind, "fall"),
            lane = math.max(0, as_int(raw.lane, 0)),
            back = raw.back == true,
          }
        end
      end
    end
  end

  if type(data.edges) == "table" then
    for _, raw in ipairs(data.edges) do
      if type(raw) == "table" then
        local from, to = as_int(raw.from, nil), as_int(raw.to, nil)
        if from and to and from >= 0 and to >= 0 and from < ninsn and to < ninsn then
          out.edges[#out.edges + 1] = { from = from, to = to, lane = math.max(0, as_int(raw.lane, 0)) }
        end
      end
    end
  end

  local pc_row = as_int(data.pc_row, nil)
  out.pc_row = (pc_row and pc_row >= 0 and pc_row < ninsn) and pc_row or nil
  local pc_block = as_int(data.pc_block, nil)
  out.pc_block = (pc_block and byid[pc_block]) and pc_block or nil
  return out
end

local function header(data, width)
  local lines, hl = {}, {}
  local fn = data.function_ or {}
  local title = fn.name or "?"
  local right = ("%s..%s"):format(fn.lo or "?", fn.hi or "?")
  lines[#lines + 1] = ui.banner(title, width, right)
  vim.list_extend(hl, ui.banner_hl(0, lines[1], title))

  -- Anything the listing rests on that is not solid is said here.
  local notes = {}
  if fn.bounded_by == "clamp" then
    notes[#notes + 1] = "cut at " .. #data.insns .. " instructions; this symbol has no recorded size"
  elseif fn.bounded_by == "window" then
    notes[#notes + 1] = "no symbol here, so these bounds are a fixed window, not a function"
  end
  local li = data.line_info or {}
  if li.why then
    notes[#notes + 1] = li.why
  end
  if data.inlined_at then
    notes[#notes + 1] = "the program counter is inside " .. data.inlined_at .. ", inlined here"
  end
  for _, note in ipairs(notes) do
    lines[#lines + 1] = "  " .. note
    hl[#hl + 1] = { #lines - 1, 0, -1, "DbgMuted" }
  end
  if #notes > 0 then
    lines[#lines + 1] = ""
  end
  return lines, hl
end

-- Test hook: lets the fuzz harness drive render() with payloads no analyser
-- would produce.
function M.__set_state(t)
  for k, v in pairs(t) do
    state[k] = v
  end
  state.error = t.error
end

function M.render()
  local buf = M.buffer()
  local width = panel.width(buf, 100)

  if state.error then
    panel.render(buf, { ui.banner("CONTROL FLOW", width), "", "  " .. state.error }, { { 2, 0, -1, "DbgWarn" } })
    return
  end
  local data = normalize(state.data)
  if not data then
    panel.render(buf, { ui.banner("CONTROL FLOW", width), "", "  Nothing stopped." }, { { 2, 0, -1, "DbgMuted" } })
    return
  end

  local lines, hl = header(data, width)
  state.first_insn_line = #lines + 1

  if state.mode == "graph" then
    local ok, box = pcall(require, "dbg.cfgbox")
    local glines, ghl = nil, nil
    if ok then
      -- Too big to draw at the level asked for is not a dead end: try the way
      -- down before refusing, and say which level it settled on.
      local okr, a, b, where, why = pcall(box.render, data, width, state.detail)
      local shown = state.detail
      while okr and not a and shown > 0 do
        shown = shown - 1
        okr, a, b, where, why = pcall(box.render, data, width, shown)
      end
      if okr and not a and why then
        lines[#lines + 1] = "  " .. why
        hl[#hl + 1] = { #lines - 1, 0, -1, "DbgWarn" }
        panel.render(buf, lines, hl)
        return
      end
      if okr and shown ~= state.detail then
        local names = { "labels only", "no addresses", "full" }
        lines[#lines + 1] = ("  too wide for %s detail, showing %s"):format(names[state.detail + 1], names[shown + 1])
        hl[#hl + 1] = { #lines - 1, 0, -1, "DbgMuted" }
      end
      if okr then
        glines, ghl = a, b
        state.boxes = {}
        for id, pos in pairs(where or {}) do
          state.boxes[id] = { row = pos.row + #lines, col = pos.col, height = pos.height, width = pos.width }
        end
      end
    end
    if glines then
      local base = #lines
      for _, l in ipairs(glines) do
        lines[#lines + 1] = l
      end
      for _, h in ipairs(ghl or {}) do
        hl[#hl + 1] = { h[1] + base, h[2], h[3], h[4] }
      end
      panel.render(buf, lines, hl)
      return
    end
    lines[#lines + 1] = "  The graph could not be built for this function; showing the listing."
    hl[#hl + 1] = { #lines - 1, 0, -1, "DbgWarn" }
    state.first_insn_line = #lines + 1
  end

  local gw = data.gutter_width or 0
  local branch_group = pc_branch_group(data)
  local pc_edge = nil
  if data.pc_row then
    for _, e in ipairs(data.edges or {}) do
      if e.from == data.pc_row then
        pc_edge = e
        break
      end
    end
  end

  -- Text first so tags align just past the longest line; right-aligning to the
  -- window pushes them too far from what they label.
  local texts, tags = {}, {}
  local widest, last_line = 0, nil
  for i, insn in ipairs(data.insns) do
    local gut = (insn.gutter or ""):gsub("%s+$", "")
    gut = gut .. string.rep(" ", math.max(0, gw - vim.fn.strchars(gut)))
    local mark = insn.is_pc and "=>" or "  "
    texts[i] = ("%s %s %s  %-" .. MNEM_WIDTH .. "s %s")
      :format(mark, gut, insn.addr, insn.mnemonic or "", insn.operands or "")
      :gsub("%s+$", "")
    widest = math.max(widest, vim.fn.strchars(texts[i]))
    -- Shown only where it changes, so one statement reads as one.
    if insn.line and insn.line ~= last_line then
      tags[i] = ("%s:%d"):format(vim.fs.basename(insn.file or "?"), insn.line)
    end
    last_line = insn.line
  end

  local tag_col = widest + 2
  for i, insn in ipairs(data.insns) do
    local row = #lines
    local text = texts[i]
    if tags[i] and tag_col + #tags[i] < width then
      text = text .. string.rep(" ", tag_col - vim.fn.strchars(text)) .. tags[i]
      hl[#hl + 1] = { row, #text - #tags[i], -1, "DbgMuted" }
    end
    local gut = (insn.gutter or ""):gsub("%s+$", "")

    lines[#lines + 1] = text

    local gut_start = 3
    local gut_end = gut_start + #gut
    if #gut > 0 then
      hl[#hl + 1] = { row, gut_start, gut_end, "DbgMuted" }
    end
    local addr_start = gut_end + 1
    hl[#hl + 1] = { row, addr_start, addr_start + #(insn.addr or ""), "DbgAddr" }
    if insn.terminator then
      local m_start = addr_start + #(insn.addr or "") + 2
      hl[#hl + 1] = { row, m_start, m_start + #(insn.mnemonic or ""), "DbgCode" }
    end
    if insn.is_pc then
      hl[#hl + 1] = { row, 0, 2, "DbgStopSign" }
    end
  end

  -- Painted last so it wins the cells the muted base covered.
  if pc_edge and branch_group and gw > 0 then
    local lane = pc_edge.lane or 0
    local from, to = math.min(pc_edge.from, pc_edge.to), math.max(pc_edge.from, pc_edge.to)
    for r = from, to do
      local row = state.first_insn_line - 1 + r
      local col = 3 + lane
      hl[#hl + 1] = { row, col, col + 1, branch_group }
    end
    for _, r in ipairs({ pc_edge.from, pc_edge.to }) do
      local row = state.first_insn_line - 1 + r
      hl[#hl + 1] = { row, 3 + lane, 3 + gw, branch_group }
    end
  end

  panel.render(buf, lines, hl)
end

function M.probe()
  local session, why = panel.stopped_session()
  if not session then
    state.data, state.error = nil, why
    M.render()
    return
  end
  state.generation = state.generation + 1
  local generation = state.generation
  gdbq.run("cfgjson", function(text, err)
    if generation ~= state.generation then
      return
    end
    if not text then
      state.data, state.error = nil, tostring(err or "cfgjson failed")
      vim.schedule(M.render)
      return
    end
    local payload = text:match("({.*})")
    -- Without `luanil` a JSON null decodes to vim.NIL, which is truthy, so every
    -- "not known" field would read as a value.
    local ok, decoded = pcall(vim.json.decode, payload or "", {
      luanil = { object = true, array = true },
    })
    if not ok or type(decoded) ~= "table" then
      state.data = nil
      state.error = "cfgjson returned no JSON. Is the kgdb toolkit loaded in this session?"
      vim.schedule(M.render)
      return
    end
    if decoded.error then
      state.data, state.error = nil, decoded.error
      vim.schedule(M.render)
      return
    end
    -- `function` is a keyword; rename once instead of quoting at every use.
    decoded.function_ = decoded["function"]
    state.data, state.error = decoded, nil
    vim.schedule(M.render)
  end, { session = session })
end

-- Biggest source window wins, ties go to the top left.  Only ordinary file
-- windows are candidates.
local function host_window()
  local best, best_area, best_row, best_col = nil, -1, nil, nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      local is_debug = ft:match("^dbg%-") ~= nil
        or ft:match("^dap%-") ~= nil
        or ft == "dap-repl"
        or ft == "dap-disassembly"
      local ok, fixed = pcall(function()
        return vim.wo[win].winfixbuf
      end)
      if not is_debug and not (ok and fixed) and vim.bo[buf].buftype == "" then
        local pos = vim.api.nvim_win_get_position(win)
        local area = vim.api.nvim_win_get_width(win) * vim.api.nvim_win_get_height(win)
        local better = area > best_area
          or (area == best_area and (pos[1] < best_row or (pos[1] == best_row and pos[2] < best_col)))
        if better then
          best, best_area, best_row, best_col = win, area, pos[1], pos[2]
        end
      end
    end
  end
  return best
end

-- A tab, not a split: the graph is the widest thing the debugger draws, so
-- halving the window would cramp both.  The window remembers its buffer so the
-- Source tab returns to that file, not to wherever the debugger last jumped.
-- An editor window, as opposed to one of the debugger's own panels: dap-view
-- pins its windows with winfixbuf, and the side column registers its own.
local function is_editor_window(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return false
  end
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local ok, fixed = pcall(function()
    return vim.wo[win].winfixbuf
  end)
  if ok and fixed then
    return false
  end
  return vim.w[win].dbg_owned == nil
end

-- The window showing the graph.  Found by looking at what is displayed, not by a
-- marker we set: reaching the buffer through the tabline is an ordinary buffer
-- switch and sets no marker, and it has to behave exactly like the command.
function M.host()
  local buf = panel.buffer("cfg")
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_editor_window(win) and vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if is_editor_window(win) and vim.w[win].dbg_cfg_prev ~= nil then
      return win
    end
  end
  return nil
end

function M.open_in_editor()
  local buf = M.buffer()
  local win = M.host() or host_window()
  if not win then
    local prev = vim.api.nvim_get_current_win()
    vim.cmd("topleft vsplit")
    win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_is_valid(prev) then
      pcall(vim.api.nvim_set_current_win, prev)
    end
  end
  local showing = vim.api.nvim_win_get_buf(win)
  if showing ~= buf then
    vim.w[win].dbg_cfg_prev = showing
  end
  pcall(vim.api.nvim_win_set_buf, win, buf)
  M.probe()
  return win
end

-- Switch the host window between its file and the graph; the first call makes
-- the host.
function M.toggle_in_editor()
  local win = M.host()
  local buf = M.buffer()
  if not win or vim.api.nvim_win_get_buf(win) ~= buf then
    return M.open_in_editor()
  end
  local prev = vim.w[win].dbg_cfg_prev
  if prev and vim.api.nvim_buf_is_valid(prev) then
    pcall(vim.api.nvim_win_set_buf, win, prev)
  else
    require("dbg.notify").warn("This window has no file to go back to.")
  end
  return win
end

function M.open()
  return M.open_in_editor()
end

-- Kept for the bottom bar, which does its own placement.
function M.open_in_panel()
  local buf = M.buffer()
  M.probe()
  return panel.show(buf, 18, "CONTROL FLOW")
end

return M
