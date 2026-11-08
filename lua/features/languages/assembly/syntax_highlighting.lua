local M = {}

local api, ts = vim.api, vim.treesitter
local ns = api.nvim_create_namespace("asm_highlight")
local START, PREFIXED, OPERANDS, STRING = 0, 1, 2, 3

local function set(words)
  local t = {}

  for word in words:gmatch("%S+") do
    t[word] = true
  end

  return t
end

local prefixes = set("lock rep repe repz repne repnz data16 data32 addr16 addr32 notrack xacquire xrelease")
local keywords = set([[byte word dword qword tword oword xmmword ymmword zmmword ptr rel
  lsl lsr asr ror rrx msl uxtb uxth uxtw uxtx sxtb sxth sxtw sxtx]])

local registers = set("sp wsp xzr wzr lr fp pc ip eip rip zero ra gp tp")
local att_registers = set("cs ds es fs gs ss st")
-- PTX special registers, written %%name in CUDA's inline assembly; %%tid.x and the like take their .x/.y/.z too.
local ptx_registers = set([[tid ntid laneid warpid nwarpid ctaid nctaid smid nsmid gridid clock clock64 clock_hi
  globaltimer globaltimer_lo globaltimer_hi lanemask_eq lanemask_le lanemask_lt lanemask_ge lanemask_gt
  dynamic_smem_size total_smem_size aggr_smem_size clusterid nclusterid cluster_ctaid cluster_nctaid
  cluster_ctarank cluster_nctarank is_explicit_cluster current_graph_exec]])

local function is_ptx_register(name)
  return ptx_registers[name] or name:find("^envreg%d+$") or name:find("^pm%d+$") or name:find("^pm%d+_64$")
end

-- PTX operand types (.pred .b32 .u64 .f16x2 .v4 ...): a GAS operand never starts with these.
local function is_ptx_type(word)
  return word == ".pred" or word:find("^%.[bsuf]%d+$") or word:find("^%.[bsuf]%d+x%d$") or word:find("^%.v[248]$")
end

local register_patterns = {
  "^[re]?[a-d]x$",
  "^[cd]r%d+$",
  "^[a-d][hl]$",
  "^[re]?[sd]i$",
  "^[re]?[sb]p$",
  "^[sd]il$",
  "^[sb]pl$",
  "^r%d+[dwb]$",
  "^[xyz]?mm%d+$",
  "^k[0-7]$",
  "^[xwvrqdshbfat]%d+$",
  "^f[tsa]%d+$",
  "^v%d+%.%d*[bhsdq]$",
  "_el[0-3]$",
}

local function is_register(word)
  if registers[word] then
    return true
  end

  for _, pattern in ipairs(register_patterns) do
    if word:find(pattern) then
      return true
    end
  end

  return false
end

local classified, classified_count = {}, 0

local function classify(word)
  local group = classified[word]

  if not group then
    local lower = word:lower()

    group = is_register(lower) and "@variable.builtin"
      or keywords[lower] and "@keyword"
      or word:find("^[A-Z][A-Z0-9_]+$") and "@constant"
      or "@variable"

    if classified_count >= 4096 then
      classified, classified_count = {}, 0
    end

    classified[word], classified_count = group, classified_count + 1
  end

  return group
end

local function at(line, pattern, i)
  local _, e = line:find(pattern, i)

  return e
end

local function number_end(line, i)
  local e = at(line, "^%d[%w_]*", i)

  return at(line, "^%.%d[%w_]*", e + 1) or e
end

local function add(out, s, e, group)
  if out then
    local n = #out

    out[n + 1], out[n + 2], out[n + 3] = s - 1, e, group
  end
end

local function percent(line, i, nasm, tmpl)
  if nasm then
    local e = at(line, "^%%[%%$]?[%w_.]+", i)

    return e or i, e and "@variable.parameter" or "@operator"
  end

  local skip = tmpl and 2 or 1
  local e = at(line, tmpl and "^%%%%[%a_][%w_]*" or "^%%[%a_][%w_]*", i)

  if e then
    local name = line:sub(i + skip, e)

    if tmpl and is_ptx_register(name) then
      return at(line, "^%.[xyz]%f[^%w_]", e + 1) or e, "@variable.builtin"
    end

    if classify(name) == "@variable.builtin" or att_registers[name:lower()] then
      return e, "@variable.builtin"
    end

    return e, line:sub(e + 1, e + 1) == "(" and "@keyword.modifier" or "@variable"
  end

  if tmpl and line:find("^%%[{|}]", i) then
    return i + 1, "@punctuation.bracket"
  end

  e = tmpl and (at(line, "^%%%a*%[[%w_]*%]", i) or at(line, "^%%%a?%d+", i) or at(line, "^%%=", i))

  return e or i, e and "@variable.parameter" or "@operator"
end

local function operand(line, i, c, nasm, tmpl)
  if c == "," then
    return i, "@punctuation.delimiter"
  elseif c == '"' then
    local k = i + 1

    while true do
      local q = line:find('[\\"]', k)

      if not q or line:sub(q, q) == '"' then
        return q or #line, "@string"
      end

      k = q + 2
    end
  elseif c == "'" then
    local e = at(line, "^'\\?.'", i) or not nasm and at(line, "^'\\?.", i)

    if e then
      return e, "@character"
    end

    return at(line, "^'[^']*'?", i), "@string"
  elseif c == "%" then
    return percent(line, i, nasm, tmpl)
  elseif c == "$" or c == "#" then
    local d = at(line, "^.%-?%d", i)

    return d and number_end(line, d) or i, d and "@number" or "@punctuation.special"
  elseif c == "=" then
    return i, line:find("^[%w_.$]", i + 1) and "@punctuation.special" or "@operator"
  elseif c == ":" then
    local e = at(line, "^:[%a_][%w_]*:", i)

    return e or i, e and "@keyword.modifier" or "@punctuation.delimiter"
  elseif c == "@" or c == "\\" then
    local e = at(line, "^.[%a_][%w_]*", i)

    return e or i, e and (c == "@" and "@keyword.modifier" or "@variable.parameter")
  elseif c:find("%d") then
    local e = not nasm and at(line, "^%d+[bf]", i)

    if e and not line:find("^[%w_.$]", e + 1) then
      return e, "@label"
    end

    return number_end(line, i), "@number"
  elseif c:find("[%a_.]") then
    local e = at(line, "^[%a_.$][%w_.$]*", i)
    local word = line:sub(i, e)

    return e, tmpl and is_ptx_type(word) and "@type" or classify(word)
  elseif c:find("[%[%](){}]") then
    return i, "@punctuation.bracket"
  elseif c:find("[-+*/|^&~!<>]") then
    return i, "@operator"
  end

  return i, nil
end

local function scan(line, i, j, state, nasm, tmpl, out)
  while i <= j do
    local c = line:sub(i, i)
    local e, group

    if c == " " or c == "\t" then
      e = (line:find("[^ \t]", i) or j + 1) - 1
    elseif c == "/" and line:sub(i + 1, i + 1) == "/" then
      e, group = j, "@comment"
    elseif c == "/" and line:sub(i + 1, i + 1) == "*" then
      e, group = at(line, "%*/", i + 2) or j, "@comment"
    else
      if state == START then
        local l = at(line, "^[%a_.$][%w_.$]*:", i) or at(line, "^%d+:", i)

        if l and l <= j and line:sub(l + 1, l + 1) ~= ":" then
          add(out, i, l - 1, "@label")
          i, e, group = l, l, "@punctuation.delimiter"
        end
      end

      -- A PTX guard (@p, @!%p1) precedes the instruction it predicates, and a PTX { } scope holds statements:
      -- neither ends the statement's start.
      if not e and state == START and c == "@" then
        e = at(line, "^@!?%%*[%a_][%w_]*", i)
        group = e and "@keyword.conditional"
      elseif not e and state == START and (c == "{" or c == "}") then
        e, group = i, "@punctuation.bracket"
      end

      if not e and state < OPERANDS then
        e = at(line, "^%.?[%a_][%w_.]*", i) or nasm and at(line, "^%%[%a_]+", i)
        if e then
          group, state = "@function.builtin", prefixes[line:sub(i, e):lower()] and PREFIXED or OPERANDS
        end
      end

      if not e and c == ";" then
        e, group, state = i, "@punctuation.delimiter", START
      elseif not e then
        state = OPERANDS
        e, group = operand(line, i, c, nasm, tmpl)
      end
    end

    e = math.min(e, j)
    if group then
      add(out, i, e, group)
    end

    i = e + 1
  end

  return state
end

local queries = {}

-- Per language and query text. Asked only with that language's tree at hand, so a failure is the grammar's (a
-- node type it lacks) and is kept too.
local function query(lang, source)
  local key = lang .. "\0" .. source

  if queries[key] == nil then
    local ok, parsed = pcall(ts.query.parse, lang, source)

    queries[key] = ok and parsed
  end

  return queries[key]
end

local cur_win, cur_buf, top_row, bot_row
local asm_file, nasm, col_limit, skips, marks, lines

local function line_at(row)
  local line = lines[row]

  if not line then
    line = api.nvim_buf_get_lines(cur_buf, row, row + 1, false)[1] or ""
    lines[row] = line
  end

  return line
end

local function row_marks(row)
  local list = marks[row]

  if not list then
    list = {}
    marks[row] = list
  end

  return list
end

local function template_text(line, i, j, state, tmpl, out)
  if state == STRING then
    add(out, i, j, "@string")

    return state
  end

  return scan(line, i, j, state, false, tmpl, out)
end

local function template_escape(text, state)
  if text == '\\"' then
    return state == STRING and OPERANDS or STRING
  elseif state ~= STRING and (text == "\\n" or text == "\\r") then
    return START
  end

  return state
end

local function has_colon(node)
  for child in node:iter_children() do
    if child:type() == ":" or child:child_count() > 0 and has_colon(child) then
      return true
    end
  end

  return false
end

local function walk(node, state, tmpl)
  for child in node:iter_children() do
    local kind = child:type()
    local sr, sc, er, ec = child:range()

    -- An ERROR that swallowed the operand ":" pulls the strings after it, constraints and clobbers, into the template.
    if sr > bot_row or kind == "ERROR" and has_colon(child) then
      return state
    elseif kind == "string_literal" then
      state = walk(child, state, tmpl)
    elseif kind == "string_content" then
      for row = sr, er do
        local line = line_at(row)
        local s, e = row == sr and sc or 0, math.min(row == er and ec or #line, #line)

        state = template_text(line, s + 1, e, state, tmpl, row >= top_row and row_marks(row) or nil)
      end
    elseif kind == "escape_sequence" then
      state = template_escape(line_at(sr):sub(sc + 1, sc + 2), state)
    elseif kind == "identifier" then
      state = OPERANDS
    end
  end

  return state
end

local function collect(ltree)
  local lang = ltree:lang()
  -- CUDA's inline assembly is PTX in device code, the host's assembly in host code: the same scan reads both.
  local q = (lang == "c" or lang == "cpp" or lang == "cuda") and query(lang, "(gnu_asm_expression) @asm")

  if q then
    local regions = ltree:included_regions()

    for i, tree in pairs(ltree:trees()) do
      local region = regions[i] or {}
      local first, last = region[1], region[#region]

      if not first or #first < 6 or first[1] <= bot_row and last[4] >= top_row then
        for _, node in q:iter_captures(tree:root(), cur_buf, top_row, bot_row + 1) do
          local code = node:field("assembly_code")[1]

          if code then
            walk(code, START, node:field("output_operands")[1] ~= nil)
          end
        end
      end
    end
  end

  for _, child in pairs(ltree:children()) do
    collect(child)
  end
end

local function on_win(_, win, buf, top, bot)
  local highlighter = ts.highlighter.active[buf]
  local parser = highlighter and highlighter.tree

  if not parser then
    return false
  end

  cur_win, cur_buf, top_row, bot_row = win, buf, top, bot
  marks, lines = {}, {}
  asm_file = parser:lang() == "asm"
  if not asm_file then
    collect(parser)

    return next(marks) ~= nil
  end

  local tree = parser:trees()[1]
  local q = query("asm", "[(line_comment) (block_comment)] @comment")

  if not tree or not q then
    return false
  end

  skips = {}
  for _, node in q:iter_captures(tree:root(), buf, top, bot + 1) do
    local sr, sc, er, ec = node:range()

    -- tree-sitter-asm reads the "#3" of "lsl #3" as a comment; queries/asm/highlights.scm skips the same nodes.
    if not line_at(sr):find("^#%d", sc + 1) then
      for row = math.max(sr, top), math.min(er, bot) do
        local list = skips[row] or {}

        skips[row] = list
        list[#list + 1] = row == sr and sc or 0
        list[#list + 1] = row == er and ec or math.huge
      end
    end
  end

  nasm = api.nvim_buf_get_name(buf):lower():sub(-4) == ".asm"
  local limit = api.nvim_get_option_value("synmaxcol", { buf = buf })

  col_limit = limit > 0 and limit or math.huge

  return true
end

local opts = { ephemeral = true, strict = false, priority = vim.hl.priorities.treesitter + 1 }

local function on_line(_, win, buf, row)
  if win ~= cur_win or buf ~= cur_buf then
    return
  end

  local out = marks[row]

  if asm_file then
    local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    local i, j, state, skip = 1, math.min(#line, col_limit), START, skips[row]

    out = {}
    for k = 1, skip and #skip or 0, 2 do
      state = scan(line, i, math.min(skip[k], j), state, nasm, false, out)
      i = skip[k + 1] + 1
    end

    scan(line, i, j, state, nasm, false, out)
  end

  for k = 1, out and #out or 0, 3 do
    opts.end_col, opts.hl_group = out[k + 1], out[k + 2]
    api.nvim_buf_set_extmark(buf, ns, row, out[k], opts)
  end
end

function M.setup()
  api.nvim_set_decoration_provider(ns, { on_win = on_win, on_line = on_line })
end

-- macro_highlight runs the same template scan on the asm strings of the #define bodies it repaints.
M.START, M.OPERANDS, M.template_text, M.template_escape = START, OPERANDS, template_text, template_escape

-- For tests: the groups one line of assembly gets, { start, end, group } each (0-based start, exclusive end).
function M._scan_line(line, inline_template)
  local out, groups = {}, {}

  scan(line, 1, #line, START, false, inline_template, out)
  for k = 1, #out, 3 do
    groups[#groups + 1] = { out[k], out[k + 1], out[k + 2] }
  end

  return groups
end

return M
