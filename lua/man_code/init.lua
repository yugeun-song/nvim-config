-- Re-highlight the code blocks inside a man page with treesitter.
--
-- syntax/man.vim pulls the legacy syntax/c.vim into sections 2 and 3, which
-- knows keywords and little else: a call and a variable are both cBlock, so
-- fprintf and fd come out the same color while a real C buffer separates them.
-- This finds the code, parses it with the parser the editor uses on a .c file,
-- and paints the result over the top.
--
-- Nothing here is specific to a page, a language or a machine. The language is
-- whatever the caller asks for, the parser is whatever nvim has, and a page
-- with no code in it comes out untouched.

local M = {}

local uv = vim.uv or vim.loop

local ns = vim.api.nvim_create_namespace("man_code")

-- Above syntax, below diagnostics. Extmarks already outrank syntax, so this
-- only orders the marks against each other.
local BASE_PRIORITY = 150

local MIN_INDENT = 2
local MIN_LINES = 2

-- Prose fed to a C parser is mostly ERROR nodes; code is not. The cut is
-- generous because one unparseable line in seventy is still a code block.
local MAX_ERROR_RATIO = 0.15

-- How many times to shrink a block and retry before giving up on it.
local MAX_SHRINKS = 3

-- An example program in a man page runs to tens of lines, not thousands: the
-- EXAMPLES block of mmap(2) is seventy. A block far past that is prose, and
-- handing one to a parser is what made cmake-modules(7) -- 37,260 lines, with a
-- single 20,123-line block -- take 774 ms to open.
local MAX_BLOCK_LINES = 800

-- Second guard, for a page that is pathological in some way this does not
-- predict. Opening a man page is interactive, so the work is bounded rather
-- than finished: blocks already painted stay painted.
local TIME_BUDGET_MS = 100

-- Prose does not open a line with a preprocessor directive, a storage class or
-- a type, and does not end one in a semicolon or a brace.
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
  "^%s*[%w_]+%s+[%w_*]+%s*%(",
}

-- @spell and @nospell steer the spell checker, @conceal the conceal machinery.
-- None of them names a highlight group.
local META_CAPTURE = { spell = true, nospell = true, conceal = true }

local function code_start(lines, first, last)
  for i = first, last do
    local l = lines[i]
    if l:match("[;{]%s*$") then return i end
    for _, pat in ipairs(CODE_OPENERS) do
      if l:match(pat) then return i end
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
      if walk(child) then return true end
    end
  end
  walk(root)
end

local function error_stats(root, len)
  if len == 0 then return 1, nil end
  local bad, first_row = 0, nil
  walk_errors(root, function(node)
    local sr, _, sb = node:start()
    local _, _, eb = node:end_()
    bad = bad + (eb - sb)
    if not first_row or sr < first_row then first_row = sr end
  end)
  return bad / len, first_row
end

local function parse(chunk, lang)
  local ok, parser = pcall(vim.treesitter.get_string_parser, chunk, lang)
  if not ok or not parser then return nil end
  local ok2, trees = pcall(parser.parse, parser)
  if not ok2 or not trees or not trees[1] then return nil end
  return trees[1]:root()
end

-- Parse from `from`, shrinking the tail back to just before the first parse
-- error when the block turns out to run into prose. A SYNOPSIS that ends in a
-- sentence about feature test macros, or one that carries a subheading and the
-- paragraph under it, converges in one or two rounds.
local function fit(lines, from, to, lang)
  for _ = 1, MAX_SHRINKS do
    if to - from + 1 < MIN_LINES then return nil end
    local chunk = table.concat(vim.list_slice(lines, from, to), "\n")
    local root = parse(chunk, lang)
    if not root then return nil end
    local ratio, first_row = error_stats(root, #chunk)
    if ratio <= MAX_ERROR_RATIO then return from, to, root, chunk end
    if not first_row or first_row == 0 then return nil end
    to = code_end(lines, from, from + first_row - 1)
    if not to then return nil end
  end
  return nil
end

local function paint(buf, root, chunk, from, lang)
  local query = vim.treesitter.query.get(lang, "highlights")
  if not query then return false end
  local seq = 0
  for id, node, metadata in query:iter_captures(root, chunk, 0, -1) do
    local name = query.captures[id]
    if name and not name:match("^_") and not META_CAPTURE[name] then
      local sr, sc, er, ec = node:range()
      seq = seq + 1
      -- A character can be captured twice: fprintf is @variable and then
      -- @function.call. The query lists the more specific capture later, so
      -- raising the priority as the walk proceeds lets it win, which is the
      -- rule the real highlighter follows.
      local prio = tonumber(metadata.priority) or (BASE_PRIORITY + seq)
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

-- Every run of indented lines, as {first, last} 1-based inclusive pairs. A man
-- page indents everything under a section heading, so a code block is always
-- one of these; so is every paragraph of prose, which is what fit() is for.
local function candidate_blocks(lines)
  local out, first = {}, nil
  for i = 1, #lines + 1 do
    local l = lines[i]
    local indented = l ~= nil and l:match("^%s") ~= nil and vim.trim(l) ~= ""
    local blank = l ~= nil and vim.trim(l) == ""
    if indented or (blank and first) then
      first = first or i
    else
      if first and i - first >= MIN_LINES then out[#out + 1] = { first, i - 1 } end
      first = nil
    end
  end
  return out
end

local function trim_blanks(lines, first, last)
  while first <= last and vim.trim(lines[first]) == "" do first = first + 1 end
  while last >= first and vim.trim(lines[last]) == "" do last = last - 1 end
  return first, last
end

local function min_indent(lines, first, last)
  local m = math.huge
  for i = first, last do
    if vim.trim(lines[i]) ~= "" then
      local n = #(lines[i]:match("^%s*") or "")
      if n < m then m = n end
    end
  end
  return m == math.huge and 0 or m
end

--- Paint every code block in a man buffer.
--- @param buf integer? buffer handle, defaults to the current one
--- @param lang string? treesitter language, defaults to c
--- @return integer blocks painted
function M.highlight(buf, lang)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  lang = lang or "c"
  local has_parser, added = pcall(vim.treesitter.language.add, lang)
  if not has_parser or added == false then return 0 end

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local painted = 0
  local started = uv.hrtime()
  for _, block in ipairs(candidate_blocks(lines)) do
    if (uv.hrtime() - started) / 1e6 > TIME_BUDGET_MS then break end
    local first, last = trim_blanks(lines, block[1], block[2])
    if last - first + 1 >= MIN_LINES and last - first + 1 <= MAX_BLOCK_LINES then
      local from = code_start(lines, first, last)
      local to = from and code_end(lines, from, last)
      -- The indent test belongs to the code, not to the block around it: a
      -- SYNOPSIS carries a one-column subheading ("Feature Test Macro
      -- Requirements...") whose indent is smaller than any line of the
      -- declarations above it, and measuring the whole block threw the
      -- declarations away with it.
      if from and to and min_indent(lines, from, to) >= MIN_INDENT then
        local f, _, root, chunk = fit(lines, from, to, lang)
        if f and paint(buf, root, chunk, f, lang) then painted = painted + 1 end
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
