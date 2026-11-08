local M = { CLIENT = "clangd_asm" }

local KEPT_CAPABILITIES = { "positionEncoding", "textDocumentSync", "definitionProvider", "hoverProvider" }

local TAG_PATTERN_SPECIALS = [[\.*$^~[]]

local CLANGD_PATIENCE_MS = 2000

local C_TYPE_KINDS = { s = true, u = true, g = true, t = true }

local NAMING_DIRECTIVES = { "set", "equ", "equiv", "eqv", "macro", "comm", "lcomm" }

local ALIAS_DIRECTIVES = { "req", "qn", "dn" }

local function in_assembler(path)
  return path:find("%.[sS]x?$") ~= nil
end

local function whole_word(symbol)
  return "%f[%w_]" .. vim.pesc(symbol) .. "%f[^%w_]"
end

-- The statement around an occurrence, up to it and without its labels.
local function statement_before(before)
  local statement, labels = before:match("[^;]*$"), 1

  while labels > 0 do
    statement, labels = statement:gsub("^%s*[%w_.$]+:", "", 1)
  end

  return statement
end

-- Whether this occurrence of a word in assembler can only be a use. Anything else may define it: a
-- label, an assignment, .req, a macro parameter, or the argument of a macro that emits a label.
local function used_here(line, first, last)
  local before, after = line:sub(1, first - 1), line:sub(last + 1)

  if before:find("\\$") then
    return true
  elseif
    line:find("^%s*#")
    or after:find("^%s*:")
    or after:find("^%s*[+%-*/|&<>]*=")
    or after:find("^%s+%.%a")
    or after:find("^[.$\\]")
  then
    return false
  end

  local statement = statement_before(before)

  if statement:find("^%s*%.$") then
    return true
  elseif statement:find("^%s*$") then
    return after:find("^%s*[,;%)]") == nil and after:find("%S") ~= nil
  elseif statement:find("^%s*%.macro%f[%s]") then
    return false
  elseif before:find("[*+%-/%%$#~!&|^%[]%s*$") then
    return true
  elseif statement:find("^%s*[%w_.$]+%s*%(") then
    return false
  end

  return before:find("%(%s*$") ~= nil
    or after:find("^%s*[%)%]*+%-/%%|&^]") ~= nil
    or (after:find("^%s*%(") ~= nil and (statement:find(",") ~= nil or after:find("^%s*%(%s*%%") ~= nil))
end

local function only_used(line, word)
  local first, last = line:find(word)

  if not first then
    return false
  end

  while first do
    if not used_here(line, first, last) then
      return false
    end

    first, last = line:find(word, last + 1)
  end

  return true
end

-- Whether this occurrence spells a definition. It only adds answers, so a form it misses costs nothing.
local function spelled_here(line, first, last)
  local before, after = line:sub(1, first - 1), line:sub(last + 1)

  if line:find("^%s*#") then
    return before:find("^%s*#%s*define%s+$") ~= nil
  end

  local statement = statement_before(before)

  if statement:find("^%s*%.?$") then
    if after:find("^%s*[:=]") then
      return true
    end

    for _, alias in ipairs(ALIAS_DIRECTIVES) do
      if after:find("^%s+%." .. alias .. "%f[^%w_]") then
        return true
      end
    end

    return false
  end

  for _, directive in ipairs(NAMING_DIRECTIVES) do
    if statement:find("^%s*%." .. directive .. "%s+$") then
      return true
    end
  end

  return false
end

local function spelled(line, word)
  local first, last = line:find(word)

  while first do
    if spelled_here(line, first, last) then
      return true
    end

    first, last = line:find(word, last + 1)
  end

  return false
end

-- cscope can miss the line that defines a word (a label, .set) and mark only its uses in that file.
local function may_define(path, word)
  local stat = vim.uv.fs_stat(path)
  local file = stat and stat.type == "file" and io.open(path, "rb")

  if not file then
    return true
  end

  local text = file:read("*a")
  local continued = false

  file:close()

  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line:find(word) and (continued or not only_used(line, word)) then
      return true
    end

    continued = line:find("\\%s*$") ~= nil
  end

  return false
end

local function hit_line(hit)
  return (hit.text:gsub("^<<.->>%s*", ""))
end

-- cscope lexes assembler as C, where a mnemonic or an operand can read as a definition. A hit goes
-- only when its line proves a use and its file leaves the word nowhere else to be defined.
function M.real_definitions(hits, symbol)
  local word = whole_word(symbol)
  local used, open_files, defining = {}, {}, {}

  for _, hit in ipairs(hits) do
    if in_assembler(hit.filename) and only_used(hit_line(hit), word) then
      used[hit] = true
    else
      open_files[hit.filename] = true
    end
  end

  return vim.tbl_filter(function(hit)
    if not used[hit] then
      return true
    elseif open_files[hit.filename] then
      return false
    end

    if defining[hit.filename] == nil then
      defining[hit.filename] = may_define(hit.filename, word)
    end

    return defining[hit.filename]
  end, hits)
end

-- A tag's address is a line number, a search pattern, or both; it is never run as a command.
local function tag_line(tag, path)
  local lnum = tonumber(tag.cmd:match("^%d+"))

  if lnum then
    return lnum, vim.fn.readfile(path, "", lnum)
  end

  local lines = vim.fn.readfile(path)
  local pattern = tag.cmd:match("^/(.*)/$") or tag.cmd:match("^%?(.*)%?$")
  local compiled, regex = pcall(vim.regex, "\\C\\M" .. (pattern or ""))

  if pattern and compiled then
    for i, line in ipairs(lines) do
      if regex:match_str(line) then
        return i, lines
      end
    end
  end
end

-- ctags' assembler parser also lists a .globl, a macro called at the start of a line as a label, and
-- a macro's use as a define.
local function defines(item, word)
  if item.kind == "p" or item.kind == "x" then
    return false
  elseif not in_assembler(item.filename) then
    return true
  elseif item.kind == "s" then
    return not item.text:find("^%s*%.%a")
  elseif item.kind == "d" then
    return not only_used(item.text, whole_word(word))
  elseif item.kind ~= "l" then
    return true
  end

  local name = vim.pesc(word)

  return item.text:find("^%s*%.?" .. name .. "%s*[:=]") ~= nil or item.text:find("^%s*" .. name .. "%s+%.%a") ~= nil
end

local function raw_tags(buf, word)
  local tagcase = vim.bo[buf].tagcase

  vim.bo[buf].tagcase = "match"
  local ok, tags =
    pcall(vim.fn.taglist, "^" .. vim.fn.escape(word, TAG_PATTERN_SPECIALS) .. "$", vim.api.nvim_buf_get_name(buf))

  vim.bo[buf].tagcase = tagcase

  return ok and tags or {}
end

-- Tags assembler could mean. Code cannot name a member, a C type or a C static of another file, nor
-- another C file's #define, as no assembler includes a .c. A macro local to another assembler file can
-- reach this one through an #include. A comment can name anything.
local function tag_entries(buf, word, in_comment)
  local file = vim.api.nvim_buf_get_name(buf)
  local items = {}

  for _, tag in ipairs(raw_tags(buf, word)) do
    local path = vim.fn.fnamemodify(tag.filename, ":p")
    local stat = vim.uv.fs_stat(path)

    local nameable = in_comment
      or not (tag.struct or tag.union or tag.class)
        and (in_assembler(path) or not C_TYPE_KINDS[tag.kind])
        and (tag.static == 0 or path == file or in_assembler(path) or (tag.kind == "d" and not path:find("%.c$")))

    -- A tags file can name anything, and reading a device or a pipe would never end.
    if nameable and stat and stat.type == "file" then
      local readable, lnum, lines = pcall(tag_line, tag, path)

      if readable and lnum then
        items[#items + 1] = { filename = path, lnum = lnum, text = lines[lnum] or "", kind = tag.kind }
      end
    end
  end

  return items
end

-- Comments blanked column for column, so what is left is code and every column still means the same.
local function blank_comments(lines)
  local code, open_comment = {}, false

  for i, line in ipairs(lines) do
    local parts, pos = {}, 1

    while pos <= #line do
      if open_comment then
        local _, close = line:find("*/", pos, true)
        local stop = close or #line

        parts[#parts + 1] = (" "):rep(stop - pos + 1)
        pos, open_comment = stop + 1, close == nil
      else
        local start = line:find("/[*/]", pos)

        if not start then
          parts[#parts + 1] = line:sub(pos)
          break
        end

        parts[#parts + 1] = line:sub(pos, start - 1)

        if line:sub(start, start + 1) == "//" then
          parts[#parts + 1] = (" "):rep(#line - start + 1)
          break
        end

        parts[#parts + 1] = "  "
        pos, open_comment = start + 2, true
      end
    end

    code[i] = table.concat(parts)
  end

  return code
end

-- The buffer's own lines that can define the word. ctags knows no .req and no label a macro call makes
-- (SYM_FUNC_ALIAS, SYM_INNER_LABEL). depth says how many #if or .if enclose each line.
local function own_occurrences(buf, word, code)
  local pattern = whole_word(word)
  local file = vim.api.nvim_buf_get_name(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local found = { spelled = {}, calls = {}, operands = {}, depth = {} }
  local depth = 0

  for lnum, line in ipairs(code) do
    if line:find("^%s*#%s*if") or line:find("^%s*%.if") then
      depth = depth + 1
    elseif line:find("^%s*#%s*endif") or line:find("^%s*%.endif") then
      depth = math.max(depth - 1, 0)
    end

    found.depth[lnum] = depth

    local first, last = line:find(pattern)
    local kind, operation

    while first and kind ~= found.spelled do
      local statement = statement_before(line:sub(1, first - 1))

      if spelled_here(line, first, last) then
        kind = found.spelled
      elseif not used_here(line, first, last) and not kind then
        if statement:find("^%s*[%a_][%w_$]*%(") then
          kind = found.calls
        elseif statement:find("^%s*[%a_][%w_$]*%s") then
          kind, operation = found.operands, statement:match("^%s*([%a_][%w_$]*)")
        elseif statement:find("^%s*$") and line:sub(last + 1):find("^%s*[,)]") then
          kind = found.calls
        end
      end

      if statement:find("^%s*$") and kind == nil then
        found.operation = true
      end

      first, last = line:find(pattern, last + 1)
    end

    if kind then
      kind[#kind + 1] = { filename = file, lnum = lnum, text = lines[lnum], operation = operation }
    end
  end

  return found
end

local function merged(...)
  local items, seen = {}, {}

  for _, list in ipairs({ ... }) do
    for _, item in ipairs(list) do
      local place = vim.fn.fnamemodify(item.filename, ":p") .. ":" .. tostring(item.lnum)

      if not seen[place] then
        seen[place] = true
        items[#items + 1] = item
      end
    end
  end

  return items
end

-- cscope answers from every database of the session; another tree's definitions are not this tree's.
local function cscope_hits(find, word, buf)
  local ok, cscope = pcall(require, "cscope")

  if not ok then
    return {}
  end

  local ran, _, hits = pcall(cscope.get_result, cscope.op_s_n[find], find, word, true)

  if not ran or not hits then
    return {}
  end

  local database =
    vim.fs.find("cscope.out", { upward = true, path = vim.fs.dirname(vim.api.nvim_buf_get_name(buf)) })[1]

  if not database then
    return hits
  end

  local root = vim.fs.dirname(database) .. "/"
  local here = vim.tbl_filter(function(hit)
    return vim.startswith(vim.fn.fnamemodify(hit.filename, ":p"), root)
  end, hits)

  return #here > 0 and here or hits
end

-- A word on a line whose operation is no assembler macro is an instruction's operand. Only with tags to
-- tell: a project without them leaves every operation in doubt.
local function emits_labels(buf, operation, own_macros)
  if #vim.fn.tagfiles() == 0 or own_macros[operation] then
    return true
  end

  for _, tag in ipairs(raw_tags(buf, operation)) do
    if tag.kind == "A" or (tag.kind == "m" and in_assembler(tag.filename)) then
      return true
    end
  end

  return false
end

local function included_files(code)
  local tails = {}

  for _, line in ipairs(code) do
    local name = line:find("include", 1, true)
      and (line:match('^%s*#%s*include%s*["<]([^">]+)[">]') or line:match('^%s*%.include%s+"([^"]+)"'))

    if name then
      tails[#tails + 1] = name:gsub("^[./]+", "")
    end
  end

  return tails
end

local function among_files(path, tails)
  for _, tail in ipairs(tails) do
    if path == tail or vim.endswith(path, "/" .. tail) then
      return true
    end
  end

  return false
end

-- What a macro call makes is in no index as a definition: SYM_INNER_LABEL(name, ...) in assembler,
-- DEFINE_PER_CPU(type, name) in C. A file whose tags define the word adds nothing but its uses.
local function macro_made(buf, word, defined_in)
  local pattern = whole_word(word)

  return vim.tbl_filter(function(ref)
    if defined_in[vim.fn.fnamemodify(ref.filename, ":p")] then
      return false
    end

    local line = hit_line(ref)

    if in_assembler(ref.filename) then
      local first, last = line:find(pattern)

      if not first or used_here(line, first, last) then
        return false
      end

      return statement_before(line:sub(1, first - 1)):find("^%s*[%a_][%w_$]*%(") ~= nil
    end

    if ref.filename:find("%.h$") and spelled(line, pattern) and not line:find("^[^#]*;%s*$") then
      return true
    end

    -- File scope is where cscope sees no function, or takes the last macro call for one.
    local context = ref.text:match("^<<(.-)>>") or ""

    if context ~= "global" and context:find("%l") or line:find("^%s*#") then
      return false
    end

    local macro = line:match("^%s*(_*%u[%u%d_]*)%s*%(")

    return macro ~= nil and line:find(pattern, #macro + 1) ~= nil
  end, cscope_hits("s", word, buf))
end

-- Nothing that may be a real definition is dropped: a tier stops the search only when it cannot be
-- wrong, or when what is left is a guess.
local function definition_items(buf, word, cursor)
  local file = vim.api.nvim_buf_get_name(buf)
  local code = blank_comments(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  local in_comment = cursor ~= nil and (code[cursor[1]] or ""):sub(cursor[2] + 1, cursor[2] + 1) == " "
  local tags = tag_entries(buf, word, in_comment)
  local own = own_occurrences(buf, word, code)

  local defining = vim.tbl_filter(function(item)
    return defines(item, word)
  end, tags)

  local at_home = merged(
    vim.tbl_filter(function(item)
      return item.filename == file
    end, defining),
    own.spelled
  )

  -- A definition inside #if or .if may not be the one built.
  local certain = #at_home > 0
    and #vim.tbl_filter(function(item)
      return (own.depth[item.lnum] or 0) > 0
    end, at_home) == 0

  if certain then
    return at_home
  end

  local word_pattern = whole_word(word)
  local hits = M.real_definitions(cscope_hits("g", word, buf), word)
  local includes = included_files(code)

  -- Outside assembler, spelling proves less: .name = is a C initializer, and C assigns as assembler defines.
  local spelled_hits = vim.tbl_filter(function(hit)
    local line = hit_line(hit)

    return spelled(line, word_pattern)
      and (
        in_assembler(hit.filename)
        or (hit.filename:find("%.h$") ~= nil and not line:find("^%s*%.") and not line:find("^[^#]*;%s*$"))
      )
  end, hits)

  local close_by = merged(
    vim.tbl_filter(function(item)
      return among_files(item.filename, includes)
    end, defining),
    vim.tbl_filter(function(hit)
      return among_files(hit.filename, includes)
    end, spelled_hits)
  )

  local own_macros = {}

  for lnum, line in ipairs(code) do
    local name = line:find(".macro", 1, true) and line:match("^%s*%.macro%s+([%w_$.]+)")

    if name then
      own_macros[name] = lnum
    end
  end

  local function macro_argument(operation)
    return emits_labels(buf, operation, own_macros)
  end

  -- A macro of this very file taking the word is most likely what makes it.
  local own_macro_arguments = vim.tbl_filter(function(item)
    return own_macros[item.operation] ~= nil
  end, own.operands)

  local defined_in = {}

  for _, item in ipairs(defining) do
    defined_in[item.filename] = true
  end

  -- A word that heads a statement is a mnemonic or a macro; no macro call makes it, and looking through
  -- every use of a word as common as ret costs a second. Nor does prose call for that search.
  local made = (own.operation or in_comment) and {} or macro_made(buf, word, defined_in)

  -- A macro call in a header more often declares what one in a source file defines.
  local made_in_sources = vim.tbl_filter(function(ref)
    return not ref.filename:find("%.h$")
  end, made)

  local likely =
    merged(at_home, close_by, own.calls, own_macro_arguments, defining, spelled_hits, made_in_sources, made)

  if #likely > 0 then
    return likely
  end

  local function own_operand(item)
    return macro_argument(item.operation)
  end

  local function assembler_hit(hit)
    if not in_assembler(hit.filename) then
      return false
    end

    local line = hit_line(hit)
    local operation = line:match("^%s*([%a_][%w_$]*)%s")

    if operation then
      return macro_argument(operation)
    end

    return not line:find("^%s*" .. vim.pesc(word) .. "%s*;?%s*$")
  end

  return merged(tags, vim.tbl_filter(own_operand, own.operands), vim.tbl_filter(assembler_hit, hits))
end

-- Read as C, instructions come back as declarations. Only what the preprocessor did is true:
-- the header an #include line names, or the #define of the word.
local function preprocessed_items(buf, win, word, done)
  local client = vim.lsp.get_clients({ bufnr = buf, name = M.CLIENT })[1]

  if not client then
    return done({})
  end

  local includes = vim.api.nvim_get_current_line():find("^%s*#%s*include") ~= nil
  local define = "^%s*#%s*define%s+" .. vim.pesc(word) .. "%f[^%w_]"
  local params = vim.lsp.util.make_position_params(win, client.offset_encoding)

  local finished = false
  local timer = assert(vim.uv.new_timer())

  local function finish(items)
    if not finished then
      finished = true
      timer:close()
      done(items)
    end
  end

  local sent, id = client:request("textDocument/definition", params, function(err, result)
    local items = {}

    if not err and result then
      local locations = vim.islist(result) and result or { result }

      for _, item in ipairs(vim.lsp.util.locations_to_items(locations, client.offset_encoding)) do
        if includes or (item.text or ""):find(define) then
          items[#items + 1] = item
        end
      end
    end

    finish(items)
  end, buf)

  if not sent then
    return finish({})
  end

  timer:start(
    CLANGD_PATIENCE_MS,
    0,
    vim.schedule_wrap(function()
      pcall(client.cancel_request, client, id)
      finish({})
    end)
  )
end

local function run_builtin(keys)
  local ok, err = pcall(vim.cmd.normal, { keys, bang = true })

  if not ok then
    vim.api.nvim_echo({ { tostring(err):match("E%d+:.*") or tostring(err), "ErrorMsg" } }, true, {})
  end
end

local function open(items, word, title)
  if #items > 1 then
    require("cscope").push_tagstack()
    vim.cmd("normal! m'")

    return require("cscope.pickers.telescope").run({ cscope = { parsed_output = items, prompt_title = title } })
  end

  local line = tonumber(items[1].lnum) - 1
  local at = { line = line, character = 0 }
  local uri = vim.uri_from_fname(vim.fn.fnamemodify(items[1].filename, ":p"))

  vim.lsp.util.show_document({ uri = uri, range = { start = at, ["end"] = at } }, "utf-8", { focus = true })
  vim.fn.search("\\C\\<" .. vim.fn.escape(word, TAG_PATTERN_SPECIALS) .. "\\>", "c", line + 1)
end

-- done(buf, items), unless the cursor left the word while clangd was answering.
local function at_word(word, done)
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)

  preprocessed_items(buf, win, word, function(items)
    if
      vim.api.nvim_get_current_win() == win
      and vim.api.nvim_win_get_buf(win) == buf
      and vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor)
    then
      done(buf, items)
    end
  end)
end

function M.definition()
  local word = vim.fn.expand("<cword>")

  -- \name is a parameter of the enclosing .macro, which no index holds.
  if word == "" or vim.fn.expand("<cWORD>"):find("\\" .. word, 1, true) then
    return run_builtin("gd")
  end

  local cursor = vim.api.nvim_win_get_cursor(0)

  at_word(word, function(buf, items)
    local title = "clangd " .. word

    if #items == 0 then
      items, title = definition_items(buf, word, cursor), "definitions of " .. word
    end

    if #items == 0 then
      return run_builtin("gd")
    end

    open(items, word, title)
  end)
end

function M.hover()
  local word = vim.fn.expand("<cword>")

  if word == "" then
    return run_builtin("K")
  end

  at_word(word, function(_, items)
    if #items > 0 then
      vim.lsp.buf.hover()
    else
      run_builtin("K")
    end
  end)
end

function M.server()
  return {
    cmd = {
      "clangd",
      "--background-index=0",
      "--clang-tidy=0",
      "--header-insertion=never",
      "--pch-storage=memory",
      "--log=error",
      "-j=" .. vim.uv.available_parallelism(),
    },
    filetypes = { "asm" },
    root_markers = {
      ".clangd",
      ".clang-tidy",
      ".clang-format",
      "compile_commands.json",
      "compile_flags.txt",
      "configure.ac",
      ".git",
    },
    handlers = { ["textDocument/publishDiagnostics"] = function() end },
    on_init = function(client)
      local kept = {}

      for _, name in ipairs(KEPT_CAPABILITIES) do
        kept[name] = client.server_capabilities[name]
      end

      client.server_capabilities = kept
    end,
    -- clangd reads assembler only when the project's configuration says how; else it answers every
    -- request with an error, and has nothing to offer this buffer.
    on_attach = function(client, buf)
      local codes = vim.lsp.protocol.ErrorCodes
      local params = {
        textDocument = vim.lsp.util.make_text_document_params(buf),
        position = { line = 0, character = 0 },
      }

      client:request("textDocument/definition", params, function(err)
        local unreadable = err and err.code ~= codes.RequestCancelled and err.code ~= codes.ContentModified

        if unreadable and client.attached_buffers[buf] then
          vim.lsp.buf_detach_client(buf, client.id)

          if vim.tbl_isempty(client.attached_buffers) then
            client:stop()
          end
        end
      end, buf)
    end,
    keys = {
      { "gd", M.definition, desc = "Goto Definition" },
      { "K", M.hover, desc = "Hover" },
    },
  }
end

local function attach(buf)
  vim.keymap.set("n", "gd", M.definition, { buffer = buf, desc = "Goto Definition" })
  vim.keymap.set("n", "K", M.hover, { buffer = buf, desc = "Hover" })
end

-- Set up by the first buffer that needs it, which is already past its FileType: that one is attached here.
function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("asm_navigation", { clear = true }),
    pattern = "asm",
    callback = function(args)
      attach(args.buf)
    end,
    desc = "gd in assembler follows clangd's preprocessor answers, tags or else cscope, then Vim's gd; K follows gd's first step",
  })

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "asm" then
      attach(buf)
    end
  end
end

return M
