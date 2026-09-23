-- Re-highlight the code blocks in a man page with the Tree-sitter parser the
-- editor uses on a source file; syntax/man.vim's legacy c.vim knows only keywords.

local M = {}

local uv = vim.uv or vim.loop

local ns = vim.api.nvim_create_namespace("man_code")

-- man.lua paints roff's bold and italic at priority 4096; anything lower is
-- covered by manBold inside a code block.
local BASE_PRIORITY = 5000

local MIN_INDENT = 2
local MIN_LINES = 2

-- Prose parsed as C is mostly ERROR nodes, code is not; generous enough that
-- one unparseable line in seventy still passes.
local MAX_ERROR_RATIO = 0.15

local MAX_SHRINKS = 3

-- Longer than any example program. cmake-modules(7) has a 20,123-line prose
-- block that took 774 ms to parse.
local MAX_BLOCK_LINES = 800

-- Opening a page is interactive: stop parsing, keep what is painted.
local TIME_BUDGET_MS = 100

-- Line shapes prose does not produce.
local CODE_OPENERS = {
  "^%s*#%s*%a",
  "^%s*typedef%s",
  "^%s*struct%s+[%w_]*%s*{",
  "^%s*union%s+[%w_]*%s*{",
  "^%s*enum%s+[%w_]*%s*{",
  "^%s*static%s",
  "^%s*extern%s",
  "^%s*const%s",
  "^%s*unsigned%s",
  "^%s*void%s",
  "^%s*int%s*$",
  "^%s*[%w_]+%s+[%w_*]+%(",
}

-- Captures that steer spell or conceal rather than name a highlight group.
local META_CAPTURE = { spell = true, nospell = true, conceal = true }

-- Share of nonblank lines ending in ; { } or opening with #. The DESCRIPTION
-- of bash(1) scores under 0.01, the EXAMPLES of mmap(2) about 0.5.
local MIN_CODE_DENSITY = 0.1

local function block_has_code(lines, first, last)
  local directives, terminators, nonblank = 0, 0, 0
  for i = first, last do
    local l = lines[i]
    if vim.trim(l) ~= "" then
      nonblank = nonblank + 1
      if l:match("^%s*#%s*%a") then
        directives = directives + 1
      elseif l:match("[;{}]%s*$") then
        terminators = terminators + 1
      end
    end
  end
  if nonblank == 0 then
    return false
  end
  return (terminators + directives) / nonblank >= MIN_CODE_DENSITY
end

local function code_start(lines, first, last)
  for i = first, last do
    local l = lines[i]
    if l:match("[;{]%s*$") then
      return i
    end
    for _, pat in ipairs(CODE_OPENERS) do
      if l:match(pat) then
        return i
      end
    end
  end
  return nil
end

local function code_end(lines, from, last)
  for i = last, from, -1 do
    local l = lines[i]
    if vim.trim(l) ~= "" and (l:match("[;}]%s*$") or l:match("^%s*#%s*%a")) then
      return i
    end
  end
  return nil
end

local function walk_errors(root, fn)
  local function walk(node)
    if node:type() == "ERROR" or node:missing() then
      return fn(node)
    end
    for child in node:iter_children() do
      if walk(child) then
        return true
      end
    end
  end
  walk(root)
end

local function error_stats(root, len)
  if len == 0 then
    return 1, nil
  end
  local bad, first_row = 0, nil
  walk_errors(root, function(node)
    local sr, _, sb = node:start()
    local _, _, eb = node:end_()
    bad = bad + (eb - sb)
    if not first_row or sr < first_row then
      first_row = sr
    end
  end)
  return bad / len, first_row
end

local function parse(chunk, lang)
  local ok, parser = pcall(vim.treesitter.get_string_parser, chunk, lang)
  if not ok or not parser then
    return nil
  end
  local ok2, trees = pcall(parser.parse, parser)
  if not ok2 or not trees or not trees[1] then
    return nil
  end
  return trees[1]:root()
end

-- Parse [from, to], cutting the tail back to before the first parse error when
-- the block runs into prose. Converges in one or two rounds.
local function fit(lines, from, to, lang)
  for _ = 1, MAX_SHRINKS do
    if to - from + 1 < MIN_LINES then
      return nil
    end
    local chunk = table.concat(vim.list_slice(lines, from, to), "\n")
    local root = parse(chunk, lang)
    if not root then
      return nil
    end
    local ratio, first_row = error_stats(root, #chunk)
    if ratio <= MAX_ERROR_RATIO then
      return from, to, root, chunk
    end
    if not first_row or first_row == 0 then
      return nil
    end
    to = code_end(lines, from, from + first_row - 1)
    if not to then
      return nil
    end
  end
  return nil
end

local function paint(buf, root, chunk, from, lang)
  local query = vim.treesitter.query.get(lang, "highlights")
  if not query then
    return false
  end
  local seq = 0
  for id, node, metadata in query:iter_captures(root, chunk, 0, -1) do
    local name = query.captures[id]
    if name and not name:match("^_") and not META_CAPTURE[name] then
      local sr, sc, er, ec = node:range()
      seq = seq + 1
      -- Later captures are more specific and must win. A query's own priority
      -- (C's @variable asks for 95) is kept, shifted up as a whole.
      local q = tonumber(metadata.priority)
      local prio = BASE_PRIORITY + (q and (q - 100) or seq)
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, from - 1 + sr, sc, {
        end_row = from - 1 + er,
        end_col = ec,
        hl_group = "@" .. name .. "." .. lang,
        priority = prio,
        strict = false,
      })
    end
  end
  return true
end

-- Runs of indented lines as 1-based inclusive {first, last}. Prose paragraphs
-- are included; fit() rejects them.
local function candidate_blocks(lines)
  local out, first = {}, nil
  for i = 1, #lines + 1 do
    local l = lines[i]
    local indented = l ~= nil and l:match("^%s") ~= nil and vim.trim(l) ~= ""
    local blank = l ~= nil and vim.trim(l) == ""
    if indented or (blank and first) then
      first = first or i
    else
      if first and i - first >= MIN_LINES then
        out[#out + 1] = { first, i - 1 }
      end
      first = nil
    end
  end
  return out
end

local function trim_blanks(lines, first, last)
  while first <= last and vim.trim(lines[first]) == "" do
    first = first + 1
  end
  while last >= first and vim.trim(lines[last]) == "" do
    last = last - 1
  end
  return first, last
end

local function min_indent(lines, first, last)
  local m = math.huge
  for i = first, last do
    if vim.trim(lines[i]) ~= "" then
      local n = #(lines[i]:match("^%s*") or "")
      if n < m then
        m = n
      end
    end
  end
  return m == math.huge and 0 or m
end

--- Paint every code block in a man buffer.
--- @param buf integer? buffer handle, defaults to the current one
--- @param lang string? treesitter language, defaults to c
--- @return integer blocks painted
function M.highlight(buf, lang)
  if not buf or buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  lang = lang or "c"
  local has_parser, added = pcall(vim.treesitter.language.add, lang)
  if not has_parser or added == false then
    return 0
  end

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local painted = 0
  local started = uv.hrtime()
  for _, block in ipairs(candidate_blocks(lines)) do
    if (uv.hrtime() - started) / 1e6 > TIME_BUDGET_MS then
      break
    end
    local first, last = trim_blanks(lines, block[1], block[2])
    if last - first + 1 >= MIN_LINES and last - first + 1 <= MAX_BLOCK_LINES then
      local from = block_has_code(lines, first, last) and code_start(lines, first, last) or nil
      local to = from and code_end(lines, from, last)
      -- Measure the indent of the code only: a SYNOPSIS subheading sits at one
      -- column and would fail the whole block.
      if from and to and min_indent(lines, from, to) >= MIN_INDENT then
        local f, _, root, chunk = fit(lines, from, to, lang)
        if f and paint(buf, root, chunk, f, lang) then
          painted = painted + 1
        end
      end
    end
  end
  return painted
end

--- Remove the highlighting from a buffer.
function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf or 0, ns, 0, -1)
end

return M
