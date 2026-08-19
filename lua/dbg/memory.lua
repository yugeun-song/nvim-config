local panel = require("dbg.panel")
local safemem = require("dbg.safemem")
local ui = require("dbg.ui")

local M = {}

local MAX_BYTES = 8192
local ANNOTATE_LIMIT = 128
local annotate_capped = false

local state = {
  source = { kind = "target", expr = nil },
  addr = nil,
  file = nil,
  per_row = 16,
  auto_width = true,
  group = 1,
  little = true,
  ascii = true,
  annotate = true,
  rows = 16,
  force = false,
  auto = true,
  phys = false,
  targets = {},
}

local bind
local symbols = {}

function M.buffer()
  local buf, created = panel.buffer("memory", "dbg-memory")
  if created then
    bind(buf)
  end
  return buf
end

function M.state()
  return state
end

local function hexsplit(s)
  s = tostring(s):gsub("^0[xX]", "")
  s = string.rep("0", math.max(0, 16 - #s)) .. s
  return tonumber(s:sub(1, 8), 16) or 0, tonumber(s:sub(9, 16), 16) or 0
end

local function hexadd(s, delta)
  local hi, lo = hexsplit(s)
  lo = lo + delta
  while lo >= 4294967296 do
    lo = lo - 4294967296
    hi = hi + 1
  end
  while lo < 0 do
    lo = lo + 4294967296
    hi = hi - 1
  end
  hi = hi % 4294967296
  return string.format("0x%08x%08x", hi, lo)
end

local function norm(addr)
  local digits = tostring(addr):gsub("^0[xX]", ""):gsub("^0+", ""):lower()
  if digits == "" then
    digits = "0"
  end
  return "0x" .. digits
end

local function per_row()
  local per = state.per_row
  if state.auto_width then
    local width = panel.width(M.buffer(), 100)
    local label = 18
    local cellw = state.group * 2 + 1
    local extra = state.ascii and 3 or 0
    local room = width - 2 - label - 2 - extra - 2
    local groups = math.max(1, math.floor(room / (cellw + (state.ascii and 1 or 0))))
    per = groups * state.group
    local caps = { 8, 16, 24, 32, 48, 64 }
    local best = state.group
    for _, c in ipairs(caps) do
      if c <= per and c % state.group == 0 then
        best = c
      end
    end
    per = best
  end
  per = per - (per % state.group)
  if per < state.group then
    per = state.group
  end
  return per
end

local function window_bytes()
  local per = per_row()
  return math.min(per * state.rows, MAX_BYTES), per
end

local function source_label()
  local s = state.source
  if s.kind == "file" then
    local f = state.file or {}
    local offset = f.offset or 0
    -- Spell out where this page sits in the file: one window of bytes looks
    -- exactly like the end of the file otherwise.
    if f.size and f.size > 0 then
      return ("%s  0x%x-0x%x of 0x%x"):format(
        vim.fs.basename(s.path or "?"),
        offset,
        math.min(f.size, offset + window_bytes()),
        f.size
      )
    end
    return ("%s +0x%x"):format(vim.fs.basename(s.path or "?"), offset)
  end
  if s.kind == "phys" then
    return "phys " .. (s.expr or state.addr or "?")
  end
  return s.expr or state.addr or "-"
end

local function subtitle()
  local bytes, per = window_bytes()
  return ("%d B  %d/row  g%d%s%s%s"):format(
    bytes,
    per,
    state.group,
    state.group > 1 and (state.little and " LE" or " BE") or "",
    state.phys and "  xp" or "",
    annotate_capped and ("  symbols: first " .. ANNOTATE_LIMIT) or ""
  )
end

local function head(extra)
  local width = panel.width(M.buffer(), 100)
  local title = extra and ("MEMORY " .. extra:upper()) or "MEMORY"
  local line = ui.banner(title, width, source_label() .. "  " .. subtitle())
  return line, title
end

local function render_rows(base, bytes, is_file)
  local per = per_row()
  local lines, hls = {}, {}
  local banner, title = head()
  lines[1] = banner
  vim.list_extend(hls, ui.banner_hl(0, banner, title))

  local i = 1
  while i <= #bytes do
    local label, rowaddr
    if is_file then
      label = string.format("%012x", (state.file.offset or 0) + i - 1)
    else
      rowaddr = hexadd(base, i - 1)
      label = rowaddr
    end
    local cells, ascii, annots = {}, {}, {}
    local k = 0
    while k < per do
      local group = {}
      for g = 0, state.group - 1 do
        group[#group + 1] = bytes:byte(i + k + g)
      end
      if #group == state.group and group[1] ~= nil then
        local text = {}
        for g = 1, state.group do
          local b = group[state.little and (state.group - g + 1) or g]
          text[#text + 1] = string.format("%02x", b or 0)
        end
        cells[#cells + 1] = table.concat(text)
        if state.group == 8 and rowaddr then
          local sym = symbols[norm(hexadd(rowaddr, k))]
          if sym then
            annots[#annots + 1] = sym
          end
        end
      else
        cells[#cells + 1] = string.rep("  ", state.group)
      end
      for g = 0, state.group - 1 do
        local b = bytes:byte(i + k + g)
        ascii[#ascii + 1] = (b and b >= 32 and b < 127) and string.char(b) or (b and "." or " ")
      end
      k = k + state.group
    end
    local line = ("  %s  %s"):format(label, table.concat(cells, " "))
    local ascii_at
    if state.ascii then
      ascii_at = #line + 2
      line = line .. ("  |%s|"):format(table.concat(ascii))
    end
    if #annots > 0 then
      line = line .. "  " .. table.concat(annots, " ")
    end
    lines[#lines + 1] = line
    local ln = #lines - 1
    hls[#hls + 1] = { ln, 2, 2 + #label, "DbgAddr" }
    if ascii_at then
      hls[#hls + 1] = { ln, ascii_at, ascii_at + per + 2, "DbgAscii" }
    end
    if #annots > 0 then
      hls[#hls + 1] = { ln, #line - #table.concat(annots, " "), #line, "DbgSymbol" }
    end
    i = i + per
  end

  if #state.targets > 0 then
    lines[#lines + 1] = ""
    local pin = ui.banner("PINNED", panel.width(M.buffer(), 100), "s switch  p pin  x unpin")
    lines[#lines + 1] = pin
    vim.list_extend(hls, ui.banner_hl(#lines - 1, pin, "PINNED"))
    for idx, t in ipairs(state.targets) do
      lines[#lines + 1] = ("    %d. %s"):format(idx, t.label)
      hls[#hls + 1] = { #lines - 1, 4, 7, "DbgKey" }
    end
  end
  panel.render(M.buffer(), lines, hls)
end

local function fail(title, detail)
  local banner, t = head(title or "error")
  panel.render(M.buffer(), {
    banner,
    "",
    "  " .. detail,
  }, vim.list_extend(ui.banner_hl(0, banner, t), { { 2, 0, 200, "DbgError" } }))
end

local function refuse(addr, verdict, why)
  state.phys = false
  local banner, t = head("refused")
  local lines = {
    banner,
    "",
    ("  %s was not read."):format(addr),
    ("  verdict: %s"):format(safemem.explain(verdict, why)),
    "",
    "  A debug read that translates outside RAM makes QEMU dispatch into a device",
    "  model, and that path can take the guest down with it, so unverified addresses",
    "  are left alone. Press o to read anyway, or :DbgSafeMem off to drop the guard.",
  }
  local hls = ui.banner_hl(0, banner, t)
  hls[#hls + 1] = { 2, 0, 200, "DbgError" }
  hls[#hls + 1] = { 3, 0, 200, "DbgWarn" }
  panel.render(M.buffer(), lines, hls)
end

local function annotate_then(base, raw, done)
  symbols = {}
  local session = panel.stopped_session()
  if not (state.annotate and state.group == 8 and session and state.source.kind ~= "file") then
    done()
    return
  end
  local count = math.floor(#raw / 8)
  if count < 1 then
    done()
    return
  end
  if count > ANNOTATE_LIMIT then
    count = ANNOTATE_LIMIT
    annotate_capped = true
  else
    annotate_capped = false
  end
  local frame = session.current_frame
  session:request("evaluate", {
    expression = ("x/%dag %s"):format(count, base),
    context = "repl",
    frameId = frame and frame.id,
  }, function(err, res)
    if not err and res then
      for line in tostring(res.result or ""):gmatch("[^\n]+") do
        local prefix, rest = line:match("^%s*(0x%x+)[^:]*:%s*(.*)$")
        if prefix then
          local index = 0
          for field in rest:gmatch("[^\t]+") do
            local value, tail = field:match("^%s*(0x%x+)%s*(.*)$")
            if value then
              local sym = tail:match("<([^>]+)>")
              if sym then
                symbols[norm(hexadd(prefix, index * 8))] = "<" .. sym .. ">"
              end
              index = index + 1
            end
          end
        end
      end
    end
    vim.schedule(done)
  end)
end

local function do_read(addr)
  local session, why = panel.stopped_session()
  if not session then
    fail(nil, why)
    return
  end
  local count = window_bytes()
  session:request("readMemory", { memoryReference = addr, count = count }, function(err, res)
    vim.schedule(function()
      if err or not res or not res.data then
        fail(
          "failed",
          "Could not read memory at "
            .. addr
            .. ": "
            .. (err and (err.message or vim.inspect(err)) or "reply carried no data")
        )
        return
      end
      local ok, raw = pcall(vim.base64.decode, res.data)
      if not ok then
        fail("failed", "base64 decode failed")
        return
      end
      state.addr = res.address or addr
      annotate_then(state.addr, raw, function()
        render_rows(state.addr, raw, false)
      end)
    end)
  end)
end

local function do_read_phys(addr)
  local session, why = panel.stopped_session()
  if not session then
    fail(nil, why)
    return
  end
  local count = window_bytes()
  safemem.read_phys(session, addr, count, function(raw, err)
    vim.schedule(function()
      if not raw then
        fail("failed", "Physical read failed at " .. addr .. ": " .. tostring(err))
        return
      end
      state.addr = addr
      symbols = {}
      render_rows(addr, raw, false)
    end)
  end)
end

local function read_file()
  local f = state.file
  if not f then
    return
  end
  local fd = vim.uv.fs_open(f.path, "r", 438)
  if not fd then
    fail("failed", "Cannot open " .. f.path)
    return
  end
  local st = vim.uv.fs_fstat(fd)
  f.size = st and st.size or 0
  if f.offset < 0 then
    f.offset = 0
  end
  if f.size > 0 and f.offset >= f.size then
    f.offset = math.max(0, f.size - window_bytes())
  end
  local data = vim.uv.fs_read(fd, window_bytes(), f.offset) or ""
  vim.uv.fs_close(fd)
  state.phys = false
  symbols = {}
  render_rows(nil, data, true)
end

local function read_at(addr)
  local session = panel.stopped_session()
  if not session then
    do_read(addr)
    return
  end
  if state.source.kind == "phys" then
    state.phys = true
    do_read_phys(addr)
    return
  end
  if state.force or not safemem.active(session) then
    state.force = false
    state.phys = false
    do_read(addr)
    return
  end
  safemem.check(session, addr, function(verdict, why)
    vim.schedule(function()
      if verdict == "ram" then
        state.phys = false
        do_read(addr)
      elseif verdict == "phys_ram" then
        state.phys = true
        do_read_phys(addr)
      else
        state.addr = addr
        refuse(addr, verdict, why)
      end
    end)
  end)
end

local function resolve(expr, cb)
  if expr:match("^0[xX]%x+$") then
    cb(expr)
    return
  end
  local session, why = panel.stopped_session()
  if not session then
    fail(nil, why)
    return
  end
  local frame = session.current_frame
  session:request("evaluate", { expression = expr, frameId = frame and frame.id, context = "watch" }, function(err, res)
    vim.schedule(function()
      if err or not res then
        fail("failed", "Could not evaluate: " .. expr)
        return
      end
      if res.memoryReference then
        cb(res.memoryReference)
        return
      end
      local hex = tostring(res.result or ""):match("0[xX](%x+)")
      if hex then
        cb("0x" .. hex)
        return
      end
      local dec = tostring(res.result or ""):match("^%s*(%d+)")
      if dec then
        cb(string.format("0x%x", tonumber(dec)))
        return
      end
      fail("failed", "No address in the result: " .. tostring(res.result))
    end)
  end)
end

function M.show_expr(expr, kind)
  if not expr or expr == "" then
    return
  end
  state.source = { kind = kind or "target", expr = expr }
  state.file = nil
  resolve(expr, read_at)
end

M.goto_expr = M.show_expr

function M.show_file(path, offset)
  path = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  if not vim.uv.fs_stat(path) then
    fail("failed", "No such file: " .. path)
    return
  end
  state.source = { kind = "file", path = path }
  state.file = { path = path, offset = offset or 0 }
  read_file()
end

-- Nothing chosen yet used to mean nothing drawn at all, which reads as a
-- broken panel rather than an empty one.  Start on the stack, and if even that
-- is not available say what the panel wants.
local function idle(reason)
  local buf = M.buffer()
  local line, title = head()
  local lines = {
    line,
    "",
    "  " .. reason,
    "",
    "  t   choose a source: a register, a symbol, an address, a physical",
    "      address, or a file on disk",
    "  L   layout: bytes per row, grouping, byte order, rows",
    "",
    "  :DbgMemory <expr|file>   set it straight away",
    "  <leader>dm               open this panel in a window of its own",
  }
  local hls = ui.banner_hl(0, line, title)
  hls[#hls + 1] = { 2, 0, 200, "DbgMuted" }
  for i = 4, #lines - 1 do
    hls[#hls + 1] = { i, 0, 6, "DbgKey" }
  end
  panel.render(buf, lines, hls)
end

function M.refresh()
  local s = state.source
  if s.kind == "file" then
    read_file()
  elseif s.expr then
    resolve(s.expr, read_at)
  elseif state.addr then
    read_at(state.addr)
  elseif panel.stopped_session() then
    state.source = { kind = "target", expr = "$sp" }
    resolve("$sp", read_at)
  else
    idle("No debug session is running.")
  end
end

function M.page(delta)
  local step = window_bytes() * delta
  if state.source.kind == "file" then
    state.file.offset = math.max(0, (state.file.offset or 0) + step)
    read_file()
    return
  end
  if not state.addr then
    return
  end
  state.source = { kind = state.source.kind, expr = nil }
  read_at(hexadd(state.addr, step))
end

function M.on_stopped()
  safemem.invalidate()
  if state.auto and state.source.kind ~= "file" then
    M.refresh()
  end
end

function M.follow()
  if state.source.kind == "file" or not state.addr then
    return
  end
  local line = vim.api.nvim_get_current_line()
  local rowaddr = line:match("^%s*(0x%x+)")
  if not rowaddr then
    return
  end
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local hexstart = 2 + #rowaddr + 2
  local cellw = state.group * 2 + 1
  local cell = math.max(0, math.floor((col - hexstart) / cellw))
  local byteoff = math.floor((cell * state.group) / 8) * 8
  local session = panel.stopped_session()
  if not session then
    return
  end
  session:request("readMemory", { memoryReference = hexadd(rowaddr, byteoff), count = 8 }, function(err, res)
    vim.schedule(function()
      if err or not res or not res.data then
        return
      end
      local raw = vim.base64.decode(res.data)
      local hi, lo = 0, 0
      for k = 7, 4, -1 do
        hi = hi * 256 + (raw:byte(k + 1) or 0)
      end
      for k = 3, 0, -1 do
        lo = lo * 256 + (raw:byte(k + 1) or 0)
      end
      M.show_expr(string.format("0x%08x%08x", hi, lo), state.source.kind)
    end)
  end)
end

function M.pin(label)
  local s = state.source
  local descriptor
  if s.kind == "file" then
    descriptor = { kind = "file", path = s.path, offset = state.file and state.file.offset or 0 }
    descriptor.label = label or ("file " .. vim.fs.basename(s.path))
  else
    descriptor = { kind = s.kind, expr = s.expr or state.addr }
    descriptor.label = label or ((s.kind == "phys" and "phys " or "") .. tostring(descriptor.expr))
  end
  if not descriptor.expr and not descriptor.path then
    return
  end
  for _, t in ipairs(state.targets) do
    if t.label == descriptor.label then
      return
    end
  end
  state.targets[#state.targets + 1] = descriptor
  M.refresh()
end

function M.unpin()
  if #state.targets == 0 then
    return
  end
  vim.ui.select(state.targets, {
    prompt = "Unpin target",
    format_item = function(t)
      return t.label
    end,
  }, function(_, idx)
    if idx then
      table.remove(state.targets, idx)
      M.refresh()
    end
  end)
end

function M.select_pinned()
  if #state.targets == 0 then
    vim.notify("No pinned targets yet; press p to pin the current one.", vim.log.levels.INFO)
    return
  end
  vim.ui.select(state.targets, {
    prompt = "Show target",
    format_item = function(t)
      return t.label
    end,
  }, function(t)
    if not t then
      return
    end
    if t.kind == "file" then
      M.show_file(t.path, t.offset)
    else
      M.show_expr(t.expr, t.kind)
    end
  end)
end

local CANDIDATES = {
  { label = "stack pointer ($sp)", expr = "$sp", universal = true },
  { label = "program counter ($pc)", expr = "$pc", universal = true },
  { label = "frame pointer ($fp)", expr = "$fp", any_reg = { "fp", "rbp", "ebp", "x29", "s0" } },
  { label = "kernel text (&_text)", expr = "&_text", sym = "_text" },
  { label = "kernel text (&_stext)", expr = "&_stext", sym = "_stext" },
  { label = "kernel data (&_sdata)", expr = "&_sdata", sym = "_sdata" },
  { label = "init task (&init_task)", expr = "&init_task", sym = "init_task" },
  { label = "init thread stack (&init_thread_union)", expr = "&init_thread_union", sym = "init_thread_union" },
  { label = "swapper page dir (&swapper_pg_dir)", expr = "&swapper_pg_dir", sym = "swapper_pg_dir" },
  { label = "environment (&environ)", expr = "&environ", sym = "environ" },
  { label = "program break (&__curbrk)", expr = "&__curbrk", sym = "__curbrk" },
  { label = "glibc main_arena (&main_arena)", expr = "&main_arena", sym = "main_arena" },
  { label = "main (&main)", expr = "&main", sym = "main" },
}

function M.available(caps)
  local out = {}
  for _, c in ipairs(CANDIDATES) do
    local ok = false
    if c.universal then
      ok = caps ~= nil
    elseif c.sym then
      ok = caps ~= nil and caps.symbols[c.sym] == true
    elseif c.any_reg then
      for _, r in ipairs(c.any_reg) do
        if caps and caps.registers[r] then
          ok = true
        end
      end
    end
    if ok then
      out[#out + 1] = c
    end
  end
  return out
end

function M.pick_source()
  require("dbg.caps").detect(nil, function(caps)
    vim.schedule(function()
      local items = {}
      for _, p in ipairs(M.available(caps)) do
        items[#items + 1] = { label = p.label, expr = p.expr, kind = "target" }
      end
      items[#items + 1] = { label = "expression or address...", ask = "expr", kind = "target" }
      if caps and caps.monitor then
        items[#items + 1] = { label = "physical address...", ask = "expr", kind = "phys" }
      end
      items[#items + 1] = { label = "file on disk...", ask = "file" }
      items[#items + 1] = { label = "the file in the current buffer", ask = "buffile" }
      items[#items + 1] = { label = "layout settings...", ask = "layout" }

      vim.ui.select(items, {
        prompt = "Hex view source (" .. require("dbg.caps").describe(caps) .. ")",
        format_item = function(i)
          return i.label
        end,
      }, function(choice)
        if not choice then
          return
        end
        if choice.ask == "expr" then
          vim.ui.input({
            prompt = choice.kind == "phys" and "Physical address: " or "Address or expression: ",
          }, function(e)
            M.show_expr(e, choice.kind)
          end)
        elseif choice.ask == "file" then
          vim.ui.input({ prompt = "File: ", completion = "file", default = vim.fn.getcwd() .. "/" }, function(f)
            if f and f ~= "" then
              M.show_file(f, 0)
            end
          end)
        elseif choice.ask == "buffile" then
          local name = vim.api.nvim_buf_get_name(0)
          if name == "" then
            vim.notify("The current buffer has no file.", vim.log.levels.WARN)
            return
          end
          M.show_file(name, 0)
        elseif choice.ask == "layout" then
          M.pick_layout()
        else
          M.show_expr(choice.expr, choice.kind)
        end
      end)
    end)
  end)
end

function M.pick_layout()
  local items = {
    { label = "bytes per row", key = "per_row", values = { 8, 16, 24, 32, 48, 64 } },
    { label = "fit row width to window", key = "auto_width", values = { true, false } },
    { label = "bytes per group", key = "group", values = { 1, 2, 4, 8 } },
    { label = "rows", key = "rows", values = { 8, 16, 24, 32, 64 } },
    { label = "group byte order", key = "little", values = { true, false } },
    { label = "ascii column", key = "ascii", values = { true, false } },
    { label = "symbol annotation (group 8)", key = "annotate", values = { true, false } },
    { label = "auto refresh on stop", key = "auto", values = { true, false } },
  }
  vim.ui.select(items, {
    prompt = "Hex view layout",
    format_item = function(i)
      return ("%-30s %s"):format(i.label, tostring(state[i.key]))
    end,
  }, function(choice)
    if not choice then
      return
    end
    vim.ui.select(choice.values, {
      prompt = choice.label,
      format_item = function(v)
        if choice.key == "little" then
          return v and "little endian" or "big endian"
        end
        return tostring(v)
      end,
    }, function(v)
      if v == nil then
        return
      end
      state[choice.key] = v
      if choice.key == "per_row" then
        state.auto_width = false
      end
      M.refresh()
    end)
  end)
end

bind = function(buf)
  local function cycle(key, order)
    return function()
      local idx = 1
      for i, v in ipairs(order) do
        if v == state[key] then
          idx = i
        end
      end
      state[key] = order[(idx % #order) + 1]
      if key == "per_row" then
        state.auto_width = false
      end
      M.refresh()
    end
  end
  local maps = {
    {
      "]]",
      function()
        M.page(1)
      end,
      "Memory: next page",
    },
    {
      "[[",
      function()
        M.page(-1)
      end,
      "Memory: prev page",
    },
    { "r", M.refresh, "Memory: refresh" },
    { "<CR>", M.follow, "Memory: follow pointer" },
    { "t", M.pick_source, "Memory: choose source" },
    { "L", M.pick_layout, "Memory: layout settings" },
    {
      "p",
      function()
        M.pin()
      end,
      "Memory: pin target",
    },
    { "x", M.unpin, "Memory: unpin target" },
    { "s", M.select_pinned, "Memory: switch pinned target" },
    { "w", cycle("per_row", { 8, 16, 24, 32, 48, 64 }), "Memory: cycle bytes per row" },
    { "g", cycle("group", { 1, 2, 4, 8 }), "Memory: cycle bytes per group" },
    {
      "+",
      function()
        state.rows = math.min(256, state.rows + 4)
        M.refresh()
      end,
      "Memory: more rows",
    },
    {
      "-",
      function()
        state.rows = math.max(2, state.rows - 4)
        M.refresh()
      end,
      "Memory: fewer rows",
    },
    {
      "e",
      function()
        state.little = not state.little
        M.refresh()
      end,
      "Memory: toggle group byte order",
    },
    {
      "A",
      function()
        state.ascii = not state.ascii
        M.refresh()
      end,
      "Memory: toggle ascii column",
    },
    {
      "N",
      function()
        state.annotate = not state.annotate
        M.refresh()
      end,
      "Memory: toggle symbol annotation",
    },
    {
      "W",
      function()
        state.auto_width = not state.auto_width
        M.refresh()
      end,
      "Memory: toggle width fitting",
    },
    {
      "o",
      function()
        state.force = true
        M.refresh()
      end,
      "Memory: read anyway, bypassing the guard",
    },
    {
      "a",
      function()
        state.auto = not state.auto
        vim.notify("Memory auto refresh " .. (state.auto and "on" or "off"), vim.log.levels.INFO)
      end,
      "Memory: toggle auto refresh",
    },
  }
  for _, m in ipairs(maps) do
    vim.keymap.set("n", m[1], m[2], { buffer = buf, nowait = true, desc = m[3] })
  end
end

function M.open(arg)
  local buf = M.buffer()
  panel.show(buf, 18, "Memory")
  if arg and arg ~= "" then
    if vim.uv.fs_stat(vim.fn.expand(arg)) then
      M.show_file(arg, 0)
    else
      M.show_expr(arg, "target")
    end
  elseif state.source.expr or state.addr or state.file then
    M.refresh()
  else
    M.pick_source()
  end
end

return M
