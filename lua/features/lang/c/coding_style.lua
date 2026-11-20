-- The C coding style where a project sets none, in C, C++ and CUDA buffers: clang-format's style without a
-- .clang-format, clangd's warnings for a file without a compile command, and a 100-column limit.
local M = {}

M.TEXT_WIDTH = 100

-- The oldest clang-format that reads every key below.
M.CLANG_FORMAT_MAJOR = 16

-- The style's warnings for a file with no compile command. clangd reads such a .h as Objective-C++, so C99's own
-- constructs are not flagged as extensions there, and -std=c99, an error there and in C++, is left out.
-- -pedantic calls clangd's preamble (leading #include lines alone) an empty translation unit if they declare nothing.
M.CLANGD_FALLBACK_FLAGS = {
  "-Wall",
  "-Wextra",
  "-pedantic",
  "-Wshadow",
  "-Wno-unused-parameter",
  "-Wno-c99-extensions",
  "-Wno-c++20-designator",
  "-Wno-empty-translation-unit",
}

-- '^[^<]' is '^"' for an #include: no double quote in --style, where a program started through cmd.exe would read one.
local INCLUDE_CATEGORIES = table.concat({
  "{Regex: '^<readline/', Priority: 1, SortPriority: 2}",
  "{Regex: '^<', Priority: 1, SortPriority: 1}",
  "{Regex: '^[^<]', Priority: 3}",
}, ", ")

-- None and false are the older spellings of {Empty: false, Inline: false, Other: false} and Block. clang-format finds
-- the main header of .c, .cc, .cpp, .cxx, .m and .mm files by itself; IncludeIsMainSourceRegex adds .cu.
local STYLE = table.concat({
  "BasedOnStyle: LLVM",
  "ColumnLimit: 0",
  "BreakBeforeBraces: Custom",
  "BraceWrapping: {AfterFunction: true}",
  "InsertBraces: true",
  "AllowShortFunctionsOnASingleLine: None",
  "AllowShortEnumsOnASingleLine: false",
  "Cpp11BracedListStyle: false",
  "AlignTrailingComments: {Kind: Never}",
  "AlignEscapedNewlines: Left",
  "IndentPPDirectives: AfterHash",
  "PPIndentWidth: 1",
  "IncludeBlocks: Regroup",
  "IncludeCategories: [" .. INCLUDE_CATEGORIES .. "]",
  "IncludeIsMainSourceRegex: '\\.cu$'",
  "InsertNewlineAtEOF: true",
}, ", ")

function M.clang_format_file(dir)
  return vim.fs.find({ ".clang-format", "_clang-format" }, { upward = true, path = dir, type = "file" })[1]
end

-- clang-format's --style for a buffer without a .clang-format, indented as the buffer is.
function M.clang_format_style(buf)
  local bo = vim.bo[buf]

  return ("{%s, IndentWidth: %d, TabWidth: %d, UseTab: %s}"):format(
    STYLE,
    bo.shiftwidth > 0 and bo.shiftwidth or bo.tabstop,
    bo.tabstop,
    bo.expandtab and "Never" or "ForIndentation"
  )
end

-- Called from FileType in a C, C++ or CUDA buffer, after the indentation. A project .editorconfig applies after
-- this and wins.
function M.apply(buf)
  local name = vim.api.nvim_buf_get_name(buf)

  if not M.clang_format_file(name == "" and vim.fn.getcwd() or vim.fs.dirname(name)) then
    vim.opt_local.textwidth = M.TEXT_WIDTH
    vim.opt_local.colorcolumn = "+1"
  end
end

-- The major version of the clang-format on PATH, or nil without one.
function M.clang_format_major()
  if vim.fn.executable("clang-format") ~= 1 then
    return nil
  end

  local ok, res = pcall(function()
    return vim.system({ "clang-format", "--version" }, { text = true }):wait(5000)
  end)

  return ok and res.code == 0 and tonumber((res.stdout or ""):match("version (%d+)")) or nil
end

return M
