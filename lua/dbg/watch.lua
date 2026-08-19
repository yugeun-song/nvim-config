local panel = require("dbg.panel")
local gdbq = require("dbg.gdbq")
local ui = require("dbg.ui")

local M = {}

-- Two columns: what the frame owns on the left, what the file owns on the
-- right.  DAP only publishes the scopes the adapter chooses -- GDB publishes
-- Arguments, Locals and Registers -- so the file-scope side is collected
-- separately.  Every stop re-checks each name, because a local's lifetime ends
-- when its block does and saying so is the point of the panel.
local SCAN_LIMIT = 4000
local NAME_LIMIT = 200
local MIN_SPLIT_WIDTH = 96

local state = {
  locals = {},
  globals = {},
  file = nil,
  truncated = false,
  frame = nil,
  previous = {},
  changed = {},
  filter = nil,
  owner = nil,
}
local token = 0

local NAME_PROBE = table
  .concat({
    'python exec("import gdb\\n',
    "out=[]\\n",
    "try:\\n",
    " st=gdb.selected_frame().find_sal().symtab\\n",
    "except Exception:\\n",
    " st=None\\n",
    "if st is None:\\n",
    " print('')\\n",
    " print(0)\\n",
    "else:\\n",
    " want=st.filename\\n",
    " seen=set()\\n",
    " scanned=0\\n",
    " for blk in [st.static_block(), st.global_block()]:\\n",
    "  if blk is None:\\n",
    "   continue\\n",
    "  for sym in blk:\\n",
    "   scanned+=1\\n",
    "   if scanned>%d:\\n",
    "    break\\n",
    "   if not sym.is_variable:\\n",
    "    continue\\n",
    "   t=getattr(sym,'symtab',None)\\n",
    "   if t is not None and t.filename!=want:\\n",
    "    continue\\n",
    "   if sym.name in seen:\\n",
    "    continue\\n",
    "   seen.add(sym.name)\\n",
    "   out.append(sym.name)\\n",
    " print(want)\\n",
    " print(len(out))\\n",
    " print('\\\\n'.join(out[:%d]))\")",
  }, "")
  :format(SCAN_LIMIT, NAME_LIMIT)

local function value_probe(list)
  return ("python exec(\"import gdb\\nfor n in %s:\\n try:\\n  v=str(gdb.parse_and_eval(n))\\n except Exception as e:\\n  v='!'+str(e)\\n print('%%s\\\\t%%s'%%(n,v.replace(chr(10),' ')))\")"):format(
    vim.json.encode(list):gsub('"', "'")
  )
end

local function liveness(value)
  if value == nil then
    return "gone"
  end
  if value:sub(1, 1) == "!" then
    return value:find("No symbol", 1, true) and "gone" or "n/a"
  end
  if value:find("optimized out", 1, true) then
    return "opt"
  end
  return "live"
end

-- What an address is, asked of kgdb rather than worked out here.  `ksym` resolves
-- a PHYSICAL or a VIRTUAL address against the same shadow symbols the session is
-- already using, so it answers before the MMU is on as well as after, which is
-- the whole point of asking during early boot.
--
-- It stops there on purpose.  Following a value onward -- dereferencing it,
-- walking it as a page table -- cannot be decided from the number: nothing in a
-- u64 says whether it is a pointer, and reading a wrong one is exactly the case
-- that takes QEMU down.  `kpt` / `kpgd` / `ktel` do those jobs in the console,
-- where you have told the tool what the value is.
function M.explain()
  local addr = vim.api.nvim_get_current_line():match("(0x%x+)")
  if not addr then
    require("dbg.notify").warn("No address on this line.")
    return
  end
  local session = panel.stopped_session()
  if not session then
    require("dbg.notify").warn("Nothing is stopped, so there is no address space to resolve against.")
    return
  end
  require("dbg.caps").detect(session, function(c)
    if not (c and c.commands and c.commands.ksym) then
      require("dbg.notify").warn("This target has no `ksym`; an address cannot be resolved here.")
      return
    end
    gdbq.run("ksym " .. addr, function(out)
      local text = vim.trim(tostring(out or ""))
      if text == "" then
        require("dbg.notify").warn(addr .. ": no answer from ksym")
        return
      end
      require("dbg.notify").info(text:gsub("%s+$", ""))
    end)
  end)
end

function M.buffer()
  local buf, created = panel.buffer("watch", "dbg-watch")
  if created then
    vim.keymap.set("n", "r", function()
      M.probe()
    end, { buffer = buf, nowait = true, desc = "Watch: refresh" })
    vim.keymap.set("n", "f", function()
      vim.ui.input({ prompt = "Name filter (empty for all): " }, function(p)
        state.filter = (p and p ~= "") and p:lower() or nil
        M.render()
      end)
    end, { buffer = buf, nowait = true, desc = "Watch: filter" })
    vim.keymap.set("n", "<CR>", function()
      local name = vim.api.nvim_get_current_line():match("[%w_]+")
      if name then
        pcall(function()
          require("dap-view").add_expr(name)
        end)
      end
    end, { buffer = buf, nowait = true, desc = "Watch: pin to the watches view" })
    vim.keymap.set("n", "K", function()
      M.explain()
    end, { buffer = buf, nowait = true, desc = "Watch: what is the address on this line" })
  end
  return buf
end

local function pass(name)
  return not state.filter or name:lower():find(state.filter, 1, true)
end

-- Padding is done by hand rather than through string.format: its width field
-- is limited to two digits, so a column wider than 99 cells raised
-- "invalid option '%-104'".  Widths are measured in display cells too, so a
-- value carrying multi-byte characters still lines up.
local function width_of(text)
  return vim.fn.strdisplaywidth(text or "")
end

local function pad(text, width)
  text = text or ""
  local short = width - width_of(text)
  return short > 0 and (text .. string.rep(" ", short)) or text
end

local function clip(text, width)
  text = text or ""
  if width_of(text) <= width then
    return text
  end
  -- "~" marks a value the column was too narrow to show in full
  local cut = vim.fn.strcharpart(text, 0, math.max(1, width - 1))
  while width_of(cut) > math.max(1, width - 1) do
    cut = vim.fn.strcharpart(cut, 0, vim.fn.strchars(cut) - 1)
  end
  return cut .. "~"
end

-- A name is either readable here or it is not listed at all; the list itself
-- is the answer.  The one case worth a word is a variable the compiler threw
-- away, because there the name is real and the value is not.
local function cell(entry, namew, valuew)
  local tag = entry.life == "opt" and "  opt" or ""
  local room = math.max(4, valuew - width_of(tag))
  local value = clip(entry.value or "-", room)
  local mark = state.changed[entry.key] and "*" or " "
  return ("%s %s %s%s"):format(mark, pad(entry.name, namew), pad(value, room), tag)
end

function M.render()
  local buf = M.buffer()
  local width = panel.width(buf, 100)
  local right = state.file and vim.fs.basename(state.file) or nil
  if state.truncated then
    right = (right or "") .. ("  first %d"):format(NAME_LIMIT)
  end
  local banner = ui.banner("WATCH", width, right)
  local lines, hls = { banner }, {}
  vim.list_extend(hls, ui.banner_hl(0, banner, "WATCH"))

  if not panel.stopped_session() then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  No debug session is running."
    hls[#hls + 1] = { 2, 0, 200, "DbgMuted" }
    panel.render(buf, lines, hls)
    return
  end

  local left, rightcol = {}, {}
  for _, e in ipairs(state.locals) do
    if pass(e.name) then
      left[#left + 1] = e
    end
  end
  for _, e in ipairs(state.globals) do
    if pass(e.name) then
      rightcol[#rightcol + 1] = e
    end
  end

  local split = width >= MIN_SPLIT_WIDTH
  local colw = split and math.floor((width - 3) / 2) or width - 2
  local function widths(list)
    local n = 6
    for _, e in ipairs(list) do
      n = math.max(n, #e.name)
    end
    n = math.min(n, math.max(6, math.floor(colw * 0.45)))
    return n, math.max(6, colw - n - 8)
  end
  local lnw, lvw = widths(left)
  local rnw, rvw = widths(rightcol)

  local function header(text, n)
    return ("%s (%d)"):format(text, n)
  end

  local function push(text, groups)
    lines[#lines + 1] = text
    local ln = #lines - 1
    for _, g in ipairs(groups or {}) do
      hls[#hls + 1] = { ln, g[1], g[2], g[3] }
    end
  end

  lines[#lines + 1] = ""
  if split then
    local lh, rh = header("LOCALS", #left), header("GLOBALS", #rightcol)
    push(
      " " .. pad(lh, colw) .. "  " .. rh,
      { { 1, 1 + #lh, "DbgPanelTitle" }, { colw + 3, colw + 3 + #rh, "DbgPanelTitle" } }
    )
    for i = 1, math.max(#left, #rightcol) do
      local l = left[i] and cell(left[i], lnw, lvw) or ""
      local r = rightcol[i] and cell(rightcol[i], rnw, rvw) or ""
      local text = " " .. pad(clip(l, colw), colw) .. "  " .. r
      lines[#lines + 1] = text
      local ln = #lines - 1
      if left[i] then
        hls[#hls + 1] = { ln, 3, 3 + lnw, state.changed[left[i].key] and "DbgChanged" or "DbgKey" }
        if left[i].life == "opt" then
          hls[#hls + 1] = { ln, math.max(0, colw - 3), colw + 1, "DbgWarn" }
        end
      end
      if rightcol[i] then
        hls[#hls + 1] = { ln, colw + 5, colw + 5 + rnw, state.changed[rightcol[i].key] and "DbgChanged" or "DbgKey" }
        if rightcol[i].life == "opt" then
          hls[#hls + 1] = { ln, math.max(0, #text - 3), #text, "DbgWarn" }
        end
      end
    end
  else
    push(" " .. header("LOCALS", #left), { { 1, 8, "DbgPanelTitle" } })
    for _, e in ipairs(left) do
      lines[#lines + 1] = " " .. cell(e, lnw, lvw)
      hls[#hls + 1] = { #lines - 1, 3, 3 + lnw, state.changed[e.key] and "DbgChanged" or "DbgKey" }
    end
    lines[#lines + 1] = ""
    push(" " .. header("GLOBALS", #rightcol), { { 1, 9, "DbgPanelTitle" } })
    for _, e in ipairs(rightcol) do
      lines[#lines + 1] = " " .. cell(e, rnw, rvw)
      hls[#hls + 1] = { #lines - 1, 3, 3 + rnw, state.changed[e.key] and "DbgChanged" or "DbgKey" }
    end
  end

  if #left == 0 and #rightcol == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  Nothing in scope here."
    hls[#hls + 1] = { #lines - 1, 0, 200, "DbgMuted" }
  end
  panel.render(buf, lines, hls)
end

-- Anything that cannot be read here simply leaves the list: a variable whose
-- block has ended is not part of what is in play any more, and an empty row
-- saying so is noise.
local function fold(kind, fresh)
  local out = {}
  for _, e in ipairs(fresh) do
    if e.life == "live" or e.life == "opt" then
      e.key = kind .. ":" .. e.name
      out[#out + 1] = e
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

local function note_changes(entries)
  for _, e in ipairs(entries) do
    local prev = state.previous[e.key]
    if prev ~= nil and prev ~= e.value then
      state.changed[e.key] = true
    end
    state.previous[e.key] = e.value
  end
end

local function collect_locals(session, cb)
  local frame = session.current_frame
  if not frame then
    cb({})
    return
  end
  session:request("scopes", { frameId = frame.id }, function(err, res)
    if err or not res then
      cb({})
      return
    end
    local wanted = {}
    for _, scope in ipairs(res.scopes or {}) do
      local name = (scope.name or ""):lower()
      if name:find("local") or name:find("argument") then
        wanted[#wanted + 1] = scope
      end
    end
    if #wanted == 0 then
      cb({})
      return
    end
    local out, pending = {}, #wanted
    for _, scope in ipairs(wanted) do
      session:request("variables", { variablesReference = scope.variablesReference }, function(e2, r2)
        if not e2 and r2 then
          for _, v in ipairs(r2.variables or {}) do
            local value = tostring(v.value or "")
            out[#out + 1] = { name = v.name, value = value, life = liveness(value) }
          end
        end
        pending = pending - 1
        if pending == 0 then
          cb(out)
        end
      end)
    end
  end)
end

function M.probe()
  local session = gdbq.session()
  if not session then
    state.locals, state.globals, state.file = {}, {}, nil
    M.render()
    return
  end
  local id = tostring(session.id or session)
  if state.owner ~= id then
    state.owner = id
    state.previous, state.changed = {}, {}
  end
  state.changed = {}
  local frame = session.current_frame
  state.frame = frame and frame.name or "?"

  token = token + 1
  local mine = token

  collect_locals(session, function(entries)
    if mine ~= token then
      return
    end
    state.locals = fold("locals", entries)
    note_changes(state.locals)
    vim.schedule(function()
      M.render()
      -- The same values feed the inline annotations, so the editor and this
      -- panel never disagree and no extra round trip is needed.
      local readable = {}
      for _, e in ipairs(state.locals) do
        if e.life == "live" then
          readable[e.name] = e.value
        end
      end
      pcall(function()
        require("dbg.inline").render(session, readable)
      end)
    end)
  end)

  local cfg = session.config or {}
  if cfg.type ~= "gdb" and cfg.type ~= "gdb_kernel" then
    state.globals, state.file = {}, nil
    return
  end

  gdbq.run(NAME_PROBE, function(text)
    if mine ~= token then
      return
    end
    -- Split rather than gmatch: the probe's first two lines are positional
    -- (file, count) and a pattern that skips or invents empty matches shifts
    -- them, which turned the count into a variable named "0".
    local rows = vim.split(tostring(text or ""), "\n", { plain = true })
    local file = vim.trim(rows[1] or "")
    local total = tonumber(vim.trim(rows[2] or "")) or 0
    local list = {}
    for i = 3, #rows do
      local name = (rows[i] or ""):match("^%s*([%w_]+)%s*$")
      if name then
        list[#list + 1] = name
      end
    end
    state.file = (file ~= "" and file) or nil
    state.truncated = total > #list
    if #list == 0 then
      state.globals = fold("globals", {})
      vim.schedule(M.render)
      return
    end
    gdbq.run(value_probe(list), function(out)
      if mine ~= token then
        return
      end
      local entries = {}
      for line in tostring(out or ""):gmatch("[^\n]+") do
        local name, value = line:match("^([%w_]+)\t(.*)$")
        if name then
          value = vim.trim(value)
          entries[#entries + 1] = { name = name, value = value, life = liveness(value) }
        end
      end
      state.globals = fold("globals", entries)
      note_changes(state.globals)
      vim.schedule(M.render)
    end)
  end)

  M.render()
end

function M.open()
  local buf = M.buffer()
  M.probe()
  panel.show(buf, 16, "Watch")
end

return M
