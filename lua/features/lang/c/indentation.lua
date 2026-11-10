-- Indentation of a C or C++ buffer: a .clang-format found upward, else 8-column tabs when the file starts more
-- lines with a tab than with two spaces, else 4 spaces. A project .editorconfig applies after this and wins.
local M = {}

local CLANG_FORMAT_STYLE_INDENT = {
  llvm = 2,
  google = 2,
  chromium = 2,
  mozilla = 2,
  webkit = 4,
  microsoft = 4,
  gnu = 2,
}

-- UseTab values (false and true are old spellings): only Never indents with spaces.
local USE_TAB_EXPANDS = {
  Never = true,
  ["false"] = true,
  ForIndentation = false,
  ForContinuationAndIndentation = false,
  AlignWithSpaces = false,
  Always = false,
  ["true"] = false,
}

-- The .clang-format documents clang-format 23 uses per extension, in order; "" is a first document without
-- Language. Older releases read .c as Cpp.
local LANGUAGE_ORDER = { c = { "C", "", "Cpp" }, h = { "Cpp", "", "C" } }

-- The top-level keys of each YAML document, quotes stripped.
local function documents(path)
  local fd = io.open(path, "r")

  if not fd then
    return nil
  end

  local docs, doc, indent = {}, nil, nil

  for line in fd:lines() do
    if line:find("^%-%-%-") or line:find("^%.%.%.") then
      doc = nil
    else
      local lead, key, value = line:match("^(%s*)([%w_]+)%s*:%s*([^#]*)")

      if key and (not doc or lead == indent) then
        if not doc then
          doc, indent = {}, lead
          docs[#docs + 1] = doc
        end

        value = vim.trim(value)
        doc[key] = value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
      end
    end
  end

  fd:close()

  return docs
end

local function inherits(keys)
  return (keys.BasedOnStyle or ""):lower() == "inheritparentconfig"
end

-- The keys a .clang-format sets for this extension, or nil when no document applies (clang-format looks higher).
local function style_keys(path, extension)
  local docs = documents(path)

  if not docs or #docs == 0 then
    return docs
  end

  local default = docs[1].Language == nil and docs[1] or nil

  for _, language in ipairs(LANGUAGE_ORDER[extension] or { "Cpp", "" }) do
    if language == "" then
      if default then
        return default
      end
    else
      for _, doc in ipairs(docs) do
        if doc.Language == language then
          return default and (not doc.BasedOnStyle or inherits(doc)) and vim.tbl_extend("force", default, doc) or doc
        end
      end
    end
  end
end

local function clang_format_indent(bufname)
  if bufname == "" then
    return nil
  end

  local files = vim.fs.find({ ".clang-format", "_clang-format" }, {
    upward = true,
    path = vim.fs.dirname(bufname),
    type = "file",
    limit = math.huge,
  })

  local extension = bufname:match("%.(%w+)$")
  local layers = {}

  for _, file in ipairs(files) do
    local keys = style_keys(file, extension)

    if keys then
      table.insert(layers, 1, keys)

      if not inherits(keys) then
        break
      end
    end
  end

  if #layers == 0 then
    return nil
  end

  local keys = {}

  for _, layer in ipairs(layers) do
    keys = vim.tbl_extend("force", keys, layer)
  end

  local based = (layers[1].BasedOnStyle or ""):lower()
  local expands = USE_TAB_EXPANDS[keys.UseTab]

  return {
    shiftwidth = tonumber(keys.IndentWidth) or CLANG_FORMAT_STYLE_INDENT[based] or 2,
    tabstop = tonumber(keys.TabWidth) or based == "microsoft" and 4 or 8,
    expandtab = expands == nil or expands,
  }
end

local function indents_with_tabs(buf)
  local tabs, spaces = 0, 0

  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, 2000, false)) do
    if line:find("^\t") then
      tabs = tabs + 1
    elseif line:find("^  ") then
      spaces = spaces + 1
    end
  end

  return tabs > spaces
end

-- Called from FileType, so vim.opt_local is that buffer and its window.
function M.apply(buf)
  local opt = vim.opt_local
  local style = clang_format_indent(vim.api.nvim_buf_get_name(buf))

  if style then
    opt.tabstop = style.tabstop
    opt.shiftwidth = style.shiftwidth
    opt.softtabstop = style.shiftwidth
    opt.expandtab = style.expandtab
  elseif indents_with_tabs(buf) then
    opt.tabstop = 8
    opt.shiftwidth = 8
    opt.softtabstop = 8
    opt.expandtab = false
  else
    opt.tabstop = 8
    opt.shiftwidth = 4
    opt.softtabstop = 4
    opt.expandtab = true
  end

  opt.list = true
  vim.b[buf].autoformat = false
end

return M
