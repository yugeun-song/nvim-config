local M = { CLIENT = "clangd_asm" }

local KEPT_CAPABILITIES = { "positionEncoding", "textDocumentSync", "definitionProvider", "hoverProvider" }

local TAG_PATTERN_SPECIALS = [[\.*$^~[]]

local CLANGD_PATIENCE_MS = 2000

local function prefer(items, wanted)
  local kept = vim.tbl_filter(wanted, items)

  return #kept > 0 and kept or items
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

-- ctags' assembler parser also lists a .globl, and a macro called at the start of a line as a label.
local function defines(item, word)
  if item.kind == "p" or item.kind == "x" then
    return false
  elseif not item.filename:find("%.[sS]x?$") or (item.kind ~= "s" and item.kind ~= "l") then
    return true
  elseif item.kind == "s" then
    return false
  end

  local name = vim.pesc(word)

  return item.text:find("^%s*%.?" .. name .. "%s*[:=]") ~= nil or item.text:find("^%s*" .. name .. "%s+%.%a") ~= nil
end

local function tag_items(buf, word)
  local file = vim.api.nvim_buf_get_name(buf)
  local tagcase = vim.bo[buf].tagcase

  vim.bo[buf].tagcase = "match"
  local ok, tags = pcall(vim.fn.taglist, "^" .. vim.fn.escape(word, TAG_PATTERN_SPECIALS) .. "$", file)

  vim.bo[buf].tagcase = tagcase

  local items = {}

  for _, tag in ipairs(ok and tags or {}) do
    local path = vim.fn.fnamemodify(tag.filename, ":p")
    local stat = vim.uv.fs_stat(path)

    -- Assembler can name a symbol or a macro, never a member. A tags file can name
    -- anything, and reading a device or a pipe would never end.
    if not (tag.struct or tag.union or tag.class) and stat and stat.type == "file" then
      local readable, lnum, lines = pcall(tag_line, tag, path)

      if readable and lnum then
        items[#items + 1] =
          { filename = path, lnum = lnum, text = lines[lnum] or "", kind = tag.kind, static = tag.static }
      end
    end
  end

  local function here(item)
    return item.filename == file
  end

  -- What does not define the name counts only when nothing does. A definition in its own
  -- file comes first, and another file's static cannot be linked to.
  items = prefer(items, function(item)
    return defines(item, word)
  end)

  items = prefer(items, function(item)
    return item.static == 0 or here(item)
  end)

  return prefer(items, here)
end

local function cscope_items(word)
  local ok, cscope = pcall(require, "cscope")

  if not ok then
    return {}
  end

  local ran, _, hits = pcall(cscope.get_result, cscope.op_s_n.g, "g", word, true)

  return ran and hits or {}
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

  at_word(word, function(buf, items)
    local title = "clangd " .. word

    if #items == 0 then
      items, title = tag_items(buf, word), "tags " .. word
    end

    if #items == 0 then
      items, title = cscope_items(word), "cscope find g " .. word
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

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("asm_navigation", { clear = true }),
    pattern = "asm",
    callback = function(args)
      vim.keymap.set("n", "gd", M.definition, { buffer = args.buf, desc = "Goto Definition" })
      vim.keymap.set("n", "K", M.hover, { buffer = args.buf, desc = "Hover" })
    end,
    desc = "gd in assembler follows clangd's preprocessor answers, tags, cscope, then Vim's gd; K follows gd's first step",
  })
end

return M
