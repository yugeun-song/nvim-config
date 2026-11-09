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

local function clang_format_indent(bufname)
  if bufname == "" then
    return nil
  end

  local found = vim.fs.find({ ".clang-format", "_clang-format" }, {
    upward = true,
    path = vim.fs.dirname(bufname),
    type = "file",
  })[1]

  local fd = found and io.open(found, "r")

  if not fd then
    return nil
  end

  local indent, tab_width, use_tab, based

  for line in fd:lines() do
    if line:match("^%-%-%-") and (indent or use_tab or based) then
      break
    end

    local key, value = line:match("^%s*([%w_]+)%s*:%s*([^#]*)")

    if key then
      value = vim.trim(value)
      if key == "IndentWidth" then
        indent = tonumber(value)
      elseif key == "TabWidth" then
        tab_width = tonumber(value)
      elseif key == "UseTab" then
        use_tab = value
      elseif key == "BasedOnStyle" then
        based = value:lower()
      end
    end
  end

  fd:close()
  indent = indent or CLANG_FORMAT_STYLE_INDENT[based] or 2

  return {
    shiftwidth = indent,
    tabstop = tab_width or 8,
    expandtab = use_tab == nil or use_tab == "Never",
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
