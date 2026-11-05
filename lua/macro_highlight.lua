local M = {}

local api, ts = vim.api, vim.treesitter
local byte, find, sub = string.byte, string.find, string.sub
local ns = api.nvim_create_namespace("macro_highlight")
local PLAIN = "MacroHighlightPlain"
local family = { c = true, cpp = true, objc = true, cuda = true }
local raw_family = { cpp = true, cuda = true }
local prefixes = { L = true, u = true, U = true, u8 = true }
local raw_prefixes = { R = true, LR = true, uR = true, UR = true, u8R = true }
local groups = {}

local function words(group, list)
  for word in list:gmatch("%S+") do
    groups[word] = group
  end
end

words("@keyword", "default goto asm __asm__")
words("@keyword.type", "enum struct union typedef")
words("@keyword.operator", "sizeof offsetof alignof _Alignof __alignof__ __alignof _alignof")
words("@keyword.return", "return")
words("@keyword.repeat", "while for do continue break")
words("@keyword.conditional", "if else case switch")
words(
  "@keyword.modifier",
  [[extern static auto register inline __inline __inline__ __forceinline thread_local __thread const constexpr
  volatile __volatile__ restrict __restrict__ __extension__ _Atomic _Noreturn noreturn _Nonnull alignas _Alignas]]
)

words(
  "@type.builtin",
  [[bool char int float double void size_t ssize_t ptrdiff_t intptr_t uintptr_t charptr_t nullptr_t max_align_t
  int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t char8_t char16_t char32_t signed unsigned long short]]
)

words("@boolean", "true false TRUE FALSE")
words(
  "@constant.builtin",
  [[NULL nullptr stderr stdin stdout __FILE__ __LINE__ __DATE__ __TIME__ __STDC__ __STDC_VERSION__ __STDC_HOSTED__
  __cplusplus __OBJC__ __ASSEMBLER__ __BASE_FILE__ __FILE_NAME__ __INCLUDE_LEVEL__ __TIMESTAMP__ __clang__
  __clang_major__ __clang_minor__ __clang_patchlevel__ __clang_version__ __clang_literal_encoding__
  __clang_wide_literal_encoding__ __FUNCTION__ __func__ __PRETTY_FUNCTION__ __VA_ARGS__ __VA_OPT__]]
)

words("@attribute", "__attribute__ __declspec __based __cdecl __clrcall __stdcall __fastcall __thiscall __vectorcall")
words("@punctuation.bracket", "( ) [ ] { }")
words("@punctuation.delimiter", "; : , . ::")
words("@punctuation.special", "...")
words("@keyword.conditional.ternary", "?")

local ops3 = { [">>="] = true, ["<<="] = true, ["..."] = true, ["->*"] = true }
local ops2 = {}

for op in ("-> ++ -- << >> <= >= == != && || += -= *= /= %= &= |= ^= :: ## .*"):gmatch("%S+") do
  ops2[op] = true
end

local function quoted(text, i, q)
  local stop = q == 34 and '[\\"\n]' or "[\\'\n]"
  local j = i + 1

  while true do
    local k = find(text, stop, j)

    if not k then
      return #text
    end

    local c = byte(text, k)

    if c ~= 92 then
      return c == 10 and k - 1 or k
    end

    j = k + (byte(text, k + 1) == 13 and byte(text, k + 2) == 10 and 3 or 2)
  end
end

local function raw_string(text, i)
  local delim = text:match('^"([^%s()\\]*)%(', i)

  if not delim or #delim > 16 then
    return quoted(text, i, 34)
  end

  local _, e = find(text, ")" .. delim .. '"', i + #delim + 2, true)

  return e or #text
end

local function line_comment(text, i)
  local j = i

  while true do
    local k = find(text, "\n", j, true)

    if not k then
      return #text
    end

    local p = byte(text, k - 1) == 13 and k - 2 or k - 1

    if byte(text, p) ~= 92 then
      return k - 1
    end

    j = k + 1
  end
end

local function number_end(text, i)
  local j = i

  while true do
    local e = select(2, find(text, "^[%w_.]*", j)) or j - 1
    local c, p = byte(text, e + 1), byte(text, e)

    if (c == 43 or c == 45) and (p == 101 or p == 69 or p == 112 or p == 80) then
      j = e + 2
    elseif c == 39 and find(text, "^[%w_]", e + 2) then
      j = e + 2
    else
      return e
    end
  end
end

local function escape_end(text, k)
  local c = byte(text, k + 1)

  if c == 120 then
    local _, e = find(text, "^%x%x?%x?%x?", k + 2)

    return e or k + 1
  elseif c == 117 or c == 85 then
    local _, e = find(text, c == 117 and "^%x%x%x%x" or "^%x%x%x%x%x%x%x%x", k + 2)

    return e or k + 1
  elseif c and c >= 48 and c <= 57 then
    local _, e = find(text, "^%d%d?%d?", k + 1)

    return e or k + 1
  elseif c == 13 and byte(text, k + 2) == 10 then
    return k + 2
  end

  return math.min(k + 1, #text)
end

-- One token per literal, comment, word or operator: kinds[n] is "s"/"c" for string/char literals, hls[n] its group.
local function lex(text, raw)
  local kinds, hls, ss, es = {}, {}, {}, {}
  local n, i, len, prev = 0, 1, #text, nil

  while i <= len do
    local _, w = find(text, "^%s+", i)

    if w then
      i = w + 1
    else
      local c, d = byte(text, i), byte(text, i + 1)
      local e, kind, group, word = i, nil, nil, nil

      if c == 47 and d == 47 then
        e, group = line_comment(text, i), "@comment"
      elseif c == 47 and d == 42 then
        local _, close = find(text, "*/", i + 2, true)

        e = close or len
        group = sub(text, i, e):find("^/%*%*[^*].*%*/$") and "@comment.documentation" or "@comment"
      elseif c == 34 or c == 39 then
        e, kind = quoted(text, i, c), c == 34 and "s" or "c"
        group = kind == "s" and "@string" or "@character"
      elseif c >= 48 and c <= 57 or c == 46 and d and d >= 48 and d <= 57 then
        e, group = number_end(text, i), "@number"
      elseif find(text, "^[%a_$\128-\255]", i) then
        e = select(2, find(text, "^[%w_$\128-\255]+", i)) or i
        word = sub(text, i, e)

        local q = byte(text, e + 1)

        if q == 34 and raw and raw_prefixes[word] then
          e, kind, group = raw_string(text, e + 1), "s", "@string"
        elseif (q == 34 or q == 39) and prefixes[word] then
          e, kind = quoted(text, e + 1, q), q == 34 and "s" or "c"
          group = kind == "s" and "@string" or "@character"
        else
          local call = find(text, "^[ \t]*%(", e + 1)

          group = groups[word]
          if not group then
            if prev == "." or prev == "->" then
              group = call and "@function.call" or "@property"
            elseif call then
              group = "@function.call"
            elseif find(word, "^[A-Z][A-Z0-9_]+$") then
              group = "@constant"
            else
              group = "@variable"
            end
          end
        end
      elseif c ~= 92 then
        word = sub(text, i, i + 2)
        if not ops3[word] then
          word = sub(word, 1, 2)
          if not ops2[word] then
            word = sub(word, 1, 1)
          end
        end

        e = i + #word - 1
        group = groups[word] or (find(word, "^[-+*/%%=<>!&|^~#.:]") and "@operator")
      end

      n = n + 1
      kinds[n], hls[n], ss[n], es[n] = kind, group, i, e
      if group ~= "@comment" and group ~= "@comment.documentation" then
        prev = word
      end

      i = e + 1
    end
  end

  return kinds, hls, ss, es, n
end

local lit_queries = {}

local function literal_query(lang)
  local q = lit_queries[lang]

  if q == nil then
    local ok, parsed = pcall(ts.query.parse, lang, "[(string_literal) (char_literal) (raw_string_literal)] @l")

    if not ok then
      ok, parsed = pcall(ts.query.parse, lang, "[(string_literal) (char_literal)] @l")
    end

    q = ok and parsed or false
    lit_queries[lang] = q
  end

  return q
end

local function tree_literals(tree, lang, buf, sb, eb, out)
  local q = literal_query(lang)

  if not q then
    return
  end

  for _, node in q:iter_captures(tree:root(), buf) do
    local _, _, nsb = node:start()
    local _, _, neb = node:end_()

    if nsb >= sb and neb <= eb then
      out[#out + 1] = { nsb - sb, neb - sb, node:type() == "char_literal" and "c" or "s" }
    end
  end
end

local function nested_literals(ltree, lang, buf, sb, eb, out)
  local inner = ltree:children()[lang]

  if not inner then
    return
  end

  for _, tree in pairs(inner:trees()) do
    local _, _, tsb, _, _, teb = tree:root():range(true)

    if tsb < eb and teb > sb then
      tree_literals(tree, lang, buf, sb, eb, out)
    end
  end

  nested_literals(inner, lang, buf, sb, eb, out)
end

local function first_mismatch(kinds, ss, es, n, theirs)
  table.sort(theirs, function(a, b)
    return a[1] < b[1]
  end)

  local j = 1

  for k = 1, n do
    if kinds[k] then
      local t = theirs[j]

      if not t or t[1] ~= ss[k] - 1 or t[2] ~= es[k] or t[3] ~= kinds[k] then
        return math.min(ss[k] - 1, t and t[1] or math.huge)
      end

      j = j + 1
    end
  end

  return theirs[j] and theirs[j][1]
end

-- Each row's list starts with the span the PLAIN layer covers, then start, end, group per token.
local function add(rows, row, s, e, hl)
  local list = rows[row]

  if not list then
    list = { s, e }
    rows[row] = list
  elseif e > list[2] then
    list[2] = e
  end

  if hl then
    list[#list + 1], list[#list + 2], list[#list + 3] = s, e, hl
  end
end

local asm_ok, asm = pcall(require, "asm_highlight")
local asm_words = { asm = true, __asm__ = true, __asm = true }
local asm_quals = { volatile = true, __volatile__ = true, inline = true, __inline__ = true, ["goto"] = true }

-- A template is what asm_highlight reads from the parse tree: depth-0 strings and identifiers before ":" or ")".
local function templates(text, kinds, ss, es, n)
  local found, k = {}, 1

  while k <= n do
    if not kinds[k] and asm_words[sub(text, ss[k], es[k])] then
      local j = k + 1

      while j <= n and asm_quals[sub(text, ss[j], es[j])] do
        j = j + 1
      end

      if j <= n and sub(text, ss[j], es[j]) == "(" then
        local toks, depth, tmpl = {}, 0, false

        j = j + 1
        while j <= n do
          local t = sub(text, ss[j], es[j])

          if depth == 0 and (t == ")" or t == ":") then
            tmpl = t == ":"
            break
          elseif t == "(" then
            depth = depth + 1
          elseif t == ")" then
            depth = depth - 1
          elseif depth == 0 and (kinds[j] == "s" or not kinds[j] and find(t, "^[%a_$\128-\255]")) then
            toks[#toks + 1] = j
          end

          j = j + 1
        end

        found[#found + 1] = { tmpl = tmpl, toks = toks }
      end

      k = j
    end

    k = k + 1
  end

  return found
end

local function scan_templates(text, kinds, ss, es, n, raw, starts, sc, from, rows)
  if not asm_ok then
    return
  end

  local r = 1

  for _, t in ipairs(templates(text, kinds, ss, es, n)) do
    local state = asm.START

    for _, k in ipairs(t.toks) do
      if not kinds[k] then
        state = asm.OPERANDS
      elseif not (raw and find(text, '^[LuU8]*R"', ss[k])) then
        local q = find(text, '"', ss[k], true)
        local last = byte(text, es[k]) == 34 and es[k] > q and es[k] - 1 or es[k]
        local a = q + 1

        while a <= last do
          local b = find(text, "\\", a, true)
          local stop = b and b <= last and b or last + 1

          if stop > a then
            while starts[r + 1] and starts[r + 1] <= a do
              r = r + 1
            end

            local out = a >= from and rows[r - 1] and {} or nil

            state = asm.template_text(text, a, stop - 1, state, t.tmpl, out)
            if out and #out > 0 then
              local base = starts[r] - 1 - (r == 1 and sc or 0)
              local list = rows[r - 1]
              local dst = list.asm or {}

              list.asm = dst
              for m = 1, #out, 3 do
                dst[#dst + 1], dst[#dst + 2], dst[#dst + 3] = out[m] - base, out[m + 1] - base, out[m + 2]
              end
            end
          end

          if stop <= last then
            state = asm.template_escape(sub(text, stop, stop + 1), state)
            a = escape_end(text, stop) + 1
          else
            a = stop
          end
        end
      end
    end
  end
end

-- tree-sitter's error recovery can skip one quote (a macro as an asm template, #x, a##b); every later
-- \-continued line of the body then shows code as string and string as code.
local function compute(buf, ltree, lang, tree, region, lines, text)
  local _, sc, sb, _, _, eb = unpack(region)
  local kinds, hls, ss, es, n = lex(text, raw_family[lang])
  local theirs = {}

  tree_literals(tree, lang, buf, sb, eb, theirs)
  nested_literals(ltree, lang, buf, sb, eb, theirs)

  local cut = first_mismatch(kinds, ss, es, n, theirs)

  if not cut then
    return false
  end

  local starts, pos = {}, 1

  for r = 1, #lines do
    starts[r] = pos
    pos = pos + #lines[r] + 1
  end

  local r = 1

  while starts[r + 1] and starts[r + 1] <= cut + 1 do
    r = r + 1
  end

  local from, rows = starts[r], {}

  for k = 1, n do
    local s, e = ss[k], es[k]

    if e >= from then
      s = math.max(s, from)
      while starts[r + 1] and starts[r + 1] <= s do
        r = r + 1
      end

      local row, hl = r, hls[k]
      local escapes = kinds[k] and not (raw_family[lang] and find(text, '^[LuU8]*R"', ss[k]))

      while s <= e do
        local line_end = starts[row + 1] and starts[row + 1] - 2 or #text
        local seg_e = math.min(e, line_end)
        local base = starts[row] - 1 - (row == 1 and sc or 0)

        if seg_e >= s then
          if escapes then
            local a = s

            while a <= seg_e do
              local b = find(text, "\\", a, true)
              local stop = b and b <= seg_e and b or seg_e + 1

              if stop > a then
                add(rows, row - 1, a - 1 - base, stop - 1 - base, hl)
              end

              if stop <= seg_e then
                local x = math.min(escape_end(text, stop), seg_e)

                add(rows, row - 1, stop - 1 - base, x - base, "@string.escape")
                a = x + 1
              else
                a = stop
              end
            end
          else
            add(rows, row - 1, s - 1 - base, seg_e - base, hl)
          end
        end

        s = line_end + 2
        row = row + 1
      end
    end
  end

  scan_templates(text, kinds, ss, es, n, raw_family[lang], starts, sc, from, rows)

  return rows
end

local cache = setmetatable({}, { __mode = "k" })
local results, result_count = {}, 0
local none = {}
local cur_win, cur_buf, marks

local function body_rows(buf, bodies, lang, tree, region, tick, settled)
  local entry = cache[tree]

  if entry and entry.tick == tick then
    return entry.rows
  end

  local sr, sc, _, er, ec = unpack(region)
  local ok, lines = pcall(api.nvim_buf_get_text, buf, sr, sc, er, ec, {})

  if not ok then
    return false
  end

  local text = table.concat(lines, "\n")
  local rows

  if not find(text, "[\"']") then
    rows = false
  else
    local hit = results[text]

    if hit and hit.lang == lang and hit.sc == sc then
      rows = hit.rows
    else
      rows = compute(buf, bodies, lang, tree, region, lines, text)
      if settled then
        if result_count >= 1024 then
          results, result_count = {}, 0
        end

        results[text], result_count = { lang = lang, sc = sc, rows = rows }, result_count + 1
      end
    end
  end

  -- Mid-parse, nested trees can lag behind the body's tree; keep such a result for this redraw only.
  if settled then
    cache[tree] = { tick = tick, rows = rows }
  end

  return rows
end

local function visit(ltree, buf, top, bot, tick, settled)
  local lang = ltree:lang()
  local bodies = family[lang] and ltree:children()[lang]

  if bodies then
    local regions = bodies:included_regions()

    for i, tree in pairs(bodies:trees()) do
      local region = regions[i]
      local first = region and region[1]

      if first and #region == 1 and #first == 6 and first[1] <= bot and first[4] >= top then
        for r, list in pairs(body_rows(buf, bodies, lang, tree, first, tick, settled) or none) do
          local row = first[1] + r

          if row >= top and row <= bot then
            marks[row] = list
          end
        end
      end
    end
  end

  for child_lang, child in pairs(ltree:children()) do
    if child_lang ~= lang then
      visit(child, buf, top, bot, tick, settled)
    end
  end
end

local function on_win(_, win, buf, top, bot)
  local highlighter = ts.highlighter.active[buf]
  local parser = highlighter and highlighter.tree

  if not parser then
    return false
  end

  cur_win, cur_buf, marks = win, buf, {}
  visit(parser, buf, top, bot, api.nvim_buf_get_changedtick(buf), not highlighter.parsing)

  return next(marks) ~= nil
end

-- Layers by priority, not an hl_group array: 0.12 stacks arrays in opposite orders for ephemeral and stored marks.
local plain_opts = { ephemeral = true, strict = false, priority = vim.hl.priorities.treesitter + 2, hl_group = PLAIN }
local opts = { ephemeral = true, strict = false, priority = vim.hl.priorities.treesitter + 3 }
local asm_opts = { ephemeral = true, strict = false, priority = vim.hl.priorities.treesitter + 4 }

local function on_line(_, win, buf, row)
  local list = win == cur_win and buf == cur_buf and marks[row]

  if list then
    plain_opts.end_col = list[2]
    api.nvim_buf_set_extmark(buf, ns, row, list[1], plain_opts)
    for k = 3, #list, 3 do
      opts.end_col, opts.hl_group = list[k + 1], list[k + 2]
      api.nvim_buf_set_extmark(buf, ns, row, list[k], opts)
    end

    local tokens = list.asm

    for k = 1, tokens and #tokens or 0, 3 do
      asm_opts.end_col, asm_opts.hl_group = tokens[k + 1], tokens[k + 2]
      api.nvim_buf_set_extmark(buf, ns, row, tokens[k], asm_opts)
    end
  end
end

local function define_plain()
  local normal = api.nvim_get_hl(0, { name = "Normal", link = false })

  -- nocombine drops the bold or italic of the wrong capture underneath; fg only, so CursorLine still shows.
  api.nvim_set_hl(0, PLAIN, { fg = normal.fg, ctermfg = normal.ctermfg, nocombine = true })
end

function M.setup()
  define_plain()
  api.nvim_create_autocmd("ColorScheme", {
    group = api.nvim_create_augroup("macro_highlight", { clear = true }),
    callback = define_plain,
  })

  api.nvim_set_decoration_provider(ns, { on_win = on_win, on_line = on_line })
end

return M
