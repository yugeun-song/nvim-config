local panel = require("dbg.panel")
local gdbq = require("dbg.gdbq")
local ui = require("dbg.ui")

local M = {}

local previous = {}
local filter = nil
local arch_label = ""
local owner = nil
local generation = 0
local painted_generation = -1
local changed_set = {}
local render_token = 0

function M.buffer()
  local buf, created = panel.buffer("registers", "dbg-registers")
  if created then
    vim.keymap.set("n", "r", function()
      M.render()
    end, { buffer = buf, nowait = true, desc = "Registers: refresh" })
    vim.keymap.set("n", "f", function()
      vim.ui.input({ prompt = "Register name filter (empty for all): " }, function(p)
        M.set_filter(p)
      end)
    end, { buffer = buf, nowait = true, desc = "Registers: filter" })
    vim.keymap.set("n", "<CR>", function()
      local value = vim.api.nvim_get_current_line():match("0x%x+")
      if value then
        require("dbg.memory").show_expr(value, "target")
        require("dbg.layout").focus("memory")
      end
    end, { buffer = buf, nowait = true, desc = "Registers: open value in the hex view" })
  end
  return buf
end

local ANNOTATE_PROBE = table.concat({
  'python exec("import gdb\\n',
  "f=gdb.newest_frame()\\n",
  "out=[]\\n",
  "for r in f.architecture().registers('general'):\\n",
  " try:\\n",
  "  v=int(f.read_register(r.name))\\n",
  " except Exception:\\n",
  "  continue\\n",
  " try:\\n",
  "  s=gdb.execute('info symbol %d'%(v & ((1<<64)-1)),to_string=True).strip()\\n",
  " except Exception:\\n",
  "  s=''\\n",
  " out.append('%s|%s'%(r.name,'' if (not s or s.startswith('No symbol')) else s))\\n",
  "print('\\\\n'.join(out))\")",
}, "")

-- Both tables are built locally and handed to the callback: two renders can be
-- in flight at once (the stop listener and the sidebar refresh), and sharing
-- module state between them used to duplicate every general register.
local function collect_annotations(cb)
  local annotations, order = {}, {}
  gdbq.run(ANNOTATE_PROBE, function(text)
    if text and not text:find("Undefined command") and text:find("|") then
      for line in text:gmatch("[^\n]+") do
        local name, sym = line:match("^(%S+)|(.*)$")
        if name then
          order[#order + 1] = name
          sym = vim.trim(sym or "")
          if sym ~= "" then
            annotations[name] = "<" .. (sym:match("^(.-)%s+in section") or sym) .. ">"
          end
        end
      end
    end
    if #order > 0 then
      cb(annotations, order)
      return
    end
    gdbq.run("info registers", function(fallback)
      if fallback then
        for line in fallback:gmatch("[^\n]+") do
          local name, rest = line:match("^(%S+)%s+(0x%S+.*)$")
          if name then
            order[#order + 1] = name
            local sym = rest:match("<([^>]+)>")
            local flags = rest:match("%[%s*([^%]]-)%s*%]")
            if sym then
              annotations[name] = "<" .. sym .. ">"
            elseif flags then
              annotations[name] = "[ " .. flags .. " ]"
            end
          end
        end
      end
      cb(annotations, order)
    end)
  end)
end

-- Translation-base registers are worth decoding, because the raw value is not
-- the table address: arm64 carries an ASID above it, x86 a PCID or cache
-- attributes below it, riscv a mode and an ASID with the base shifted.  Which
-- ones exist is read from the target's own register set rather than assumed
-- from an architecture name, so a target that has none simply shows none.
local TRANSLATION = {
  { name = "cr3", role = "page tables" },
  { name = "satp", role = "supervisor page tables" },
  { name = "TTBR0_EL1", role = "low half (user / identity)" },
  { name = "TTBR1_EL1", role = "high half (kernel)" },
  { name = "TTBR0_EL2", role = "EL2 low half" },
  { name = "VTTBR_EL2", role = "stage 2" },
}

local SATP_MODE = { [0] = "bare", [8] = "sv39", [9] = "sv48", [10] = "sv57", [11] = "sv64" }

local function hex16(value)
  local digits = tostring(value or ""):match("0[xX](%x+)") or tostring(value or ""):match("^%s*(%x+)%s*$")
  if not digits then
    return nil
  end
  digits = digits:lower()
  if #digits > 16 then
    digits = digits:sub(-16)
  end
  return string.rep("0", 16 - #digits) .. digits
end

local function tidy(digits)
  local trimmed = digits:gsub("^0+", "")
  return "0x" .. (trimmed == "" and "0" or trimmed)
end

local function decode_translation(name, value, byname)
  local s = hex16(value)
  if not s then
    return nil
  end
  if name == "cr3" then
    local base = s:sub(1, 13) .. "000"
    local low = tonumber(s:sub(14, 16), 16) or 0
    local cr4 = hex16((byname["cr4"] or {}).value)
    local pcide = cr4 and (math.floor((tonumber(cr4:sub(12, 16), 16) or 0) / 0x20000) % 2) == 1
    local extra = ""
    if pcide then
      extra = ("  pcid %d"):format(low)
    elseif low ~= 0 then
      extra = ("  flags 0x%x"):format(low)
    end
    return ("base %s%s"):format(tidy(base), extra)
  end
  if name == "satp" then
    local mode = tonumber(s:sub(1, 1), 16) or 0
    local asid = tonumber(s:sub(2, 5), 16) or 0
    local ppn = s:sub(6, 16)
    if mode == 0 then
      return "bare, no translation"
    end
    return ("%s  base %s%s"):format(
      SATP_MODE[mode] or ("mode " .. mode),
      tidy(ppn .. "000"),
      asid ~= 0 and ("  asid %d"):format(asid) or ""
    )
  end
  -- arm64 TTBRn: ASID in [63:48], table base in [47:1], CnP in bit 0
  local asid = tonumber(s:sub(1, 4), 16) or 0
  local last = tonumber(s:sub(16, 16), 16) or 0
  local base = "0000" .. s:sub(5, 15) .. ("%x"):format(last - (last % 2))
  return ("base %s%s"):format(tidy(base), asid ~= 0 and ("  asid %d"):format(asid) or "")
end

local function translation_rows(byname)
  local rows = {}
  for _, entry in ipairs(TRANSLATION) do
    local reg = byname[entry.name]
    if reg then
      local decoded = decode_translation(entry.name, reg.value, byname)
      if decoded then
        rows[#rows + 1] = { name = entry.name, role = entry.role, detail = decoded }
      end
    end
  end
  return rows
end

local function fmt_value(v)
  local value = tostring(v.value or "")
  if value == "" then
    if v.variablesReference and v.variablesReference ~= 0 then
      return "{" .. (v.type or "...") .. "}"
    end
    return "-"
  end
  return value
end

local function paint(vars, annotations, general_order)
  local buf = M.buffer()
  local width = panel.width(buf, 100)
  local byname, general, others = {}, {}, {}
  for _, v in ipairs(vars) do
    byname[v.name] = v
  end
  local isgeneral = {}
  for _, name in ipairs(general_order) do
    if byname[name] and not isgeneral[name] then
      isgeneral[name] = true
      general[#general + 1] = byname[name]
    end
  end
  for _, v in ipairs(vars) do
    if not isgeneral[v.name] then
      others[#others + 1] = v
    end
  end

  if painted_generation ~= generation then
    painted_generation = generation
    changed_set = {}
    for _, v in ipairs(vars) do
      if previous[v.name] ~= nil and previous[v.name] ~= v.value then
        changed_set[v.name] = true
      end
    end
    previous = {}
    for _, v in ipairs(vars) do
      previous[v.name] = v.value
    end
  end

  local function passes(v)
    return not filter or v.name:lower():find(filter, 1, true)
  end

  local lines, hls = {}, {}
  local banner = ui.banner(
    "REGISTERS",
    width,
    ("%d total  %s%s"):format(#vars, arch_label, filter and ("  filter=" .. filter) or "")
  )
  lines[1] = banner
  vim.list_extend(hls, ui.banner_hl(0, banner, banner:match("%[ (%S+) %]") or "REGISTERS"))

  if filter and #vim.tbl_filter(passes, general) == 0 and #vim.tbl_filter(passes, others) == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  No register name contains " .. filter .. "."
    hls[#hls + 1] = { #lines - 1, 0, 200, "DbgMuted" }
    panel.render(buf, lines, hls)
    return
  end

  local shown_general = vim.tbl_filter(passes, general)
  local namew = 6
  for _, v in ipairs(shown_general) do
    namew = math.max(namew, #v.name)
  end
  for _, v in ipairs(shown_general) do
    local value = fmt_value(v)
    local changed = changed_set[v.name] == true
    local mark = changed and "*" or " "
    local ann = annotations[v.name]
    if ann and value:find("<", 1, true) then
      ann = nil
    end
    local line = (" %s %s%s  %-20s%s"):format(
      mark,
      v.name,
      string.rep(" ", namew - #v.name),
      value,
      ann and ("  " .. ann) or ""
    )
    lines[#lines + 1] = line
    local ln = #lines - 1
    hls[#hls + 1] = { ln, 1, 2, changed and "DbgChanged" or "DbgMuted" }
    hls[#hls + 1] = { ln, 3, 3 + namew, changed and "DbgChanged" or "DbgKey" }
    if ann then
      hls[#hls + 1] = { ln, #line - #ann, #line, "DbgSymbol" }
    end
  end

  local translation = translation_rows(byname)
  if #translation > 0 and not filter then
    lines[#lines + 1] = ""
    local sub = ui.banner("TRANSLATION", width, ("%d"):format(#translation))
    lines[#lines + 1] = sub
    vim.list_extend(hls, ui.banner_hl(#lines - 1, sub, "TRANSLATION"))
    local tw = 6
    for _, row in ipairs(translation) do
      tw = math.max(tw, #row.name)
    end
    for _, row in ipairs(translation) do
      local line = ("  %s%s  %-34s%s"):format(
        row.name,
        string.rep(" ", tw - #row.name),
        row.detail,
        row.role and ("  " .. row.role) or ""
      )
      lines[#lines + 1] = line
      local ln = #lines - 1
      hls[#hls + 1] = { ln, 2, 2 + tw, "DbgKey" }
      if row.role then
        hls[#hls + 1] = { ln, math.max(0, #line - #row.role), #line, "DbgMuted" }
      end
    end
  end

  local shown_others = vim.tbl_filter(passes, others)
  if #shown_others > 0 then
    lines[#lines + 1] = ""
    local sub = ui.banner("SYSTEM / VECTOR", width, ("%d"):format(#shown_others))
    lines[#lines + 1] = sub
    vim.list_extend(hls, ui.banner_hl(#lines - 1, sub, "SYSTEM / VECTOR"))

    local nw, vw = 0, 0
    for _, v in ipairs(shown_others) do
      nw = math.max(nw, #v.name)
      vw = math.max(vw, #fmt_value(v))
    end
    vw = math.min(vw, 20)
    local cell = nw + vw + 4
    local cols = math.max(1, math.floor((width - 2) / cell))
    local rows = math.ceil(#shown_others / cols)
    for r = 1, rows do
      local parts, marks = {}, {}
      for c = 0, cols - 1 do
        local v = shown_others[r + c * rows]
        if v then
          local value = fmt_value(v)
          if #value > vw then
            value = value:sub(1, vw - 1) .. "~"
          end
          local col = 2
          for _, prev in ipairs(parts) do
            col = col + #prev
          end
          local piece = v.name .. string.rep(" ", nw - #v.name) .. "  " .. value
          piece = piece .. string.rep(" ", math.max(0, cell - #piece))
          marks[#marks + 1] = { col, col + nw, changed_set[v.name] == true }
          parts[#parts + 1] = piece
        end
      end
      local line = ("  " .. table.concat(parts)):gsub("%s+$", "")
      lines[#lines + 1] = line
      local ln = #lines - 1
      for _, m in ipairs(marks) do
        hls[#hls + 1] = { ln, m[1], m[2], m[3] and "DbgChanged" or "DbgKey" }
      end
    end
  end

  panel.render(buf, lines, hls)
end

function M.render()
  local buf = M.buffer()
  local session, why = panel.stopped_session()
  if not session then
    local banner = ui.banner("REGISTERS", panel.width(buf, 100))
    panel.render(buf, { banner, "", "  " .. why }, ui.banner_hl(0, banner, "REGISTERS"))
    return
  end
  render_token = render_token + 1
  local token = render_token
  local id = tostring(session.id or session)
  if owner ~= id then
    owner = id
    previous = {}
    changed_set = {}
    generation = generation + 1
    painted_generation = -1
  end
  arch_label = (session.config or {}).arch or ""
  local frame = session.current_frame
  session:request("scopes", { frameId = frame.id }, function(err, res)
    if err or not res then
      vim.schedule(function()
        local banner = ui.banner("REGISTERS", panel.width(buf, 100), "error")
        panel.render(buf, {
          banner,
          "",
          "  Could not read scopes: " .. (err and (err.message or vim.inspect(err)) or "no reply"),
        }, vim.list_extend(ui.banner_hl(0, banner, "REGISTERS"), { { 2, 0, 200, "DbgError" } }))
      end)
      return
    end
    local target
    for _, s in ipairs(res.scopes or {}) do
      if s.presentationHint == "registers" or (s.name or ""):lower():find("register") then
        target = s
      end
    end
    if not target then
      vim.schedule(function()
        local banner = ui.banner("REGISTERS", panel.width(buf, 100))
        panel.render(buf, {
          banner,
          "",
          "  This adapter exposes no register scope.",
        }, ui.banner_hl(0, banner, "REGISTERS"))
      end)
      return
    end
    local args = { variablesReference = target.variablesReference }
    if session.capabilities and session.capabilities.supportsValueFormattingOptions then
      args.format = { hex = true }
    end
    local function expand(vars, order, done)
      local groups = {}
      for _, v in ipairs(vars) do
        if (v.value == nil or v.value == "") and v.variablesReference and v.variablesReference ~= 0 then
          groups[#groups + 1] = v
        end
      end
      if #groups == 0 or #groups ~= #vars then
        done(vars)
        return
      end
      local flat, pending = {}, #groups
      for _, g in ipairs(groups) do
        session:request("variables", { variablesReference = g.variablesReference }, function(e, r)
          if not e and r then
            local isgeneral = (g.name or ""):lower():find("general") ~= nil
            for _, child in ipairs(r.variables or {}) do
              flat[#flat + 1] = child
              if isgeneral then
                order[#order + 1] = child.name
              end
            end
          end
          pending = pending - 1
          if pending == 0 then
            done(flat)
          end
        end)
      end
    end

    session:request("variables", args, function(err2, res2)
      if err2 or not res2 then
        vim.schedule(function()
          local banner = ui.banner("REGISTERS", panel.width(buf, 100), "error")
          panel.render(buf, {
            banner,
            "",
            "  Could not read registers: " .. (err2 and (err2.message or vim.inspect(err2)) or "no reply"),
          }, vim.list_extend(ui.banner_hl(0, banner, "REGISTERS"), { { 2, 0, 200, "DbgError" } }))
        end)
        return
      end
      collect_annotations(function(annotations, order)
        expand(res2.variables or {}, order, function(flat)
          vim.schedule(function()
            if token ~= render_token then
              return
            end
            paint(flat, annotations, order)
          end)
        end)
      end)
    end)
  end)
end

-- The values from the last paint, so other panels can reason about flags and
-- register contents without asking the target again.
function M.values()
  return previous
end

function M.mark_stop()
  generation = generation + 1
end

function M.set_filter(pattern)
  filter = (pattern and pattern ~= "") and pattern:lower() or nil
  M.render()
end

function M.open()
  local buf = M.buffer()
  M.render()
  panel.show(buf, 14, "Registers")
end

return M
