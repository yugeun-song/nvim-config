-- spaceduck colorscheme for Neovim
-- An independent Lua re-implementation of the "spaceduck" theme by pineapplegiant,
-- reusing its color palette and name.
-- Original: https://github.com/pineapplegiant/spaceduck (MIT, Copyright (c) 2020 pineapplegiant)

vim.cmd("highlight clear")
vim.g.colors_name = "spaceduck"
vim.o.termguicolors = true

local p = {
  bg0       = "#0f111b",
  bg1       = "#16182a",
  bg2       = "#1b1c36",
  bg3       = "#30365F",
  fg        = "#ecf0c1",
  fg_dim    = "#c1c3a8",
  grey      = "#686f9a",
  red       = "#e33400",
  green     = "#5ccc96",
  yellow    = "#f2ce00",
  blue      = "#00a3cc",
  purple    = "#b3a1e6",
  indigo    = "#7a5ccc",
  white     = "#f0f1ce",
  sel_bg    = "#686f9a",
  sel_fg    = "#ffffff",
  none      = "NONE",
}

local function hi(group, opts)
  vim.api.nvim_set_hl(0, group, opts)
end

-- Editor UI ------------------------------------------------------------------

hi("Normal",       { fg = p.fg,   bg = vim.g.neovide and p.bg0 or p.none })
hi("NormalNC",     { fg = p.fg,   bg = vim.g.neovide and p.bg0 or p.none })
hi("NormalFloat",  { fg = p.fg,   bg = p.bg1 })
hi("FloatBorder",  { fg = p.grey, bg = p.bg1 })
hi("FloatTitle",   { fg = p.yellow, bg = p.bg1, bold = true })
hi("Cursor",       { fg = p.bg1,   bg = p.green })
hi("lCursor",      { link = "Cursor" })
hi("CursorIM",     { link = "Cursor" })
hi("TermCursor",   { link = "Cursor" })
hi("CursorLine",   { bg = p.bg1 })
hi("CursorColumn", { bg = p.bg1 })
hi("ColorColumn",  { bg = p.bg1 })
hi("LineNr",       { fg = p.grey })
hi("CursorLineNr", { fg = p.yellow, bold = true })
hi("SignColumn",   { bg = p.none })
hi("FoldColumn",   { fg = p.grey, bg = p.none })
hi("Folded",       { fg = p.grey, bg = p.bg1 })
hi("VertSplit",    { fg = p.bg3 })
hi("WinSeparator", { fg = p.bg3 })

hi("StatusLine",   { fg = p.fg,   bg = p.bg1 })
hi("StatusLineNC", { fg = p.grey, bg = p.bg1 })
hi("TabLine",      { fg = p.grey, bg = p.bg1 })
hi("TabLineFill",  { bg = p.none })
hi("TabLineSel",   { fg = p.fg,   bg = p.bg2, bold = true })
hi("WinBar",       { fg = p.fg_dim, bg = p.none })
hi("WinBarNC",     { fg = p.grey,   bg = p.none })

hi("Pmenu",        { fg = p.fg,   bg = p.bg1 })
hi("PmenuSel",     { fg = p.bg1,  bg = p.blue })
hi("PmenuSbar",    { bg = p.bg2 })
hi("PmenuThumb",   { bg = p.grey })

hi("Visual",       { bg = p.bg3 })
hi("VisualNOS",    { bg = p.bg3 })
hi("Search",       { fg = p.bg1,  bg = p.yellow })
hi("IncSearch",    { fg = p.bg1,  bg = p.green })
hi("CurSearch",    { fg = p.bg1,  bg = p.blue })
hi("Substitute",   { fg = p.bg1,  bg = p.red })

hi("MatchParen",   { fg = p.white, bg = p.bg3, bold = true })
hi("NonText",      { fg = p.bg3 })
hi("SpecialKey",   { fg = p.bg3 })
hi("Whitespace",   { fg = p.bg3 })
hi("EndOfBuffer",  { fg = p.bg1 })

hi("Directory",    { fg = p.blue })
hi("Title",        { fg = p.yellow, bold = true })
hi("Question",     { fg = p.green })
hi("MoreMsg",      { fg = p.green })
hi("ModeMsg",      { fg = p.fg_dim })
hi("WarningMsg",   { fg = p.yellow })
hi("ErrorMsg",     { fg = p.red, bold = true })

hi("WildMenu",     { fg = p.bg1, bg = p.blue })
hi("Conceal",      { fg = p.grey })
hi("SpellBad",     { undercurl = true, sp = p.red })
hi("SpellCap",     { undercurl = true, sp = p.blue })
hi("SpellLocal",   { undercurl = true, sp = p.green })
hi("SpellRare",    { undercurl = true, sp = p.purple })

-- Diff -----------------------------------------------------------------------

hi("DiffAdd",    { bg = "#0d2818" })
hi("DiffChange", { bg = "#1a1a30" })
hi("DiffDelete", { fg = "#5a1a0a", bg = "#2a0e04" })
hi("DiffText",   { bg = "#2a2a50" })
hi("Added",      { fg = p.green })
hi("Changed",    { fg = p.blue })
hi("Removed",    { fg = p.red })

-- Legacy syntax (Gruvbox/One Dark assignment pattern) ------------------------

hi("Comment",     { fg = p.grey, italic = true })
hi("Constant",    { fg = p.purple })
hi("String",      { fg = p.green })
hi("Character",   { fg = p.green })
hi("Number",      { fg = p.purple })
hi("Boolean",     { fg = p.purple, bold = true })
hi("Float",       { fg = p.purple })

hi("Identifier",  { fg = p.fg })
hi("Function",    { fg = p.green })

hi("Statement",   { fg = p.red })
hi("Conditional", { fg = p.red })
hi("Repeat",      { fg = p.red })
hi("Label",       { fg = p.red })
hi("Operator",    { fg = p.blue })
hi("Keyword",     { fg = p.red })
hi("Exception",   { fg = p.red })

hi("PreProc",     { fg = p.indigo })
hi("Include",     { fg = p.indigo })
hi("Define",      { fg = p.indigo })
hi("Macro",       { fg = p.indigo })
hi("PreCondit",   { fg = p.indigo })

hi("Type",        { fg = p.yellow })
hi("StorageClass", { fg = p.red })
hi("Structure",   { fg = p.yellow })
hi("Typedef",     { fg = p.yellow })

hi("Special",     { fg = p.indigo })
hi("SpecialChar", { fg = p.indigo })
hi("Tag",         { fg = p.red })
hi("Delimiter",   { fg = p.grey })
hi("Debug",       { fg = p.red })

hi("Underlined",  { fg = p.blue, underline = true })
hi("Ignore",      { fg = p.bg3 })
hi("Error",       { fg = p.red, bold = true })
hi("Todo",        { fg = p.bg1, bg = p.yellow, bold = true })

-- Treesitter (generic — applies to all languages) ---------------------------

hi("@variable",               { fg = p.fg })
hi("@variable.builtin",       { fg = p.purple })
hi("@variable.parameter",     { fg = p.blue })
hi("@variable.member",        { fg = p.purple })

hi("@constant",               { fg = p.yellow })
hi("@constant.builtin",       { fg = p.purple, bold = true })
hi("@constant.macro",         { fg = p.yellow })

hi("@module",                 { fg = p.blue })
hi("@label",                  { fg = p.blue })

hi("@string",                 { fg = p.green })
hi("@string.escape",          { fg = p.indigo })
hi("@string.regexp",          { fg = p.indigo })
hi("@string.special",         { fg = p.indigo })
hi("@string.special.url",     { fg = p.blue, underline = true })
hi("@string.special.symbol",  { fg = p.purple })
hi("@string.special.path",    { fg = p.green })

hi("@character",              { fg = p.green })
hi("@character.special",      { fg = p.indigo })
hi("@number",                 { fg = p.purple })
hi("@number.float",           { fg = p.purple })
hi("@boolean",                { fg = p.purple, bold = true })

hi("@type",                   { fg = p.yellow })
hi("@type.builtin",           { fg = p.yellow })
hi("@type.qualifier",         { fg = p.red })
hi("@type.definition",        { fg = p.yellow })

hi("@attribute",              { fg = p.indigo })
hi("@attribute.builtin",      { fg = p.indigo })
hi("@property",               { fg = p.purple })

hi("@function",               { fg = p.green })
hi("@function.builtin",       { fg = p.green })
hi("@function.call",          { fg = p.green })
hi("@function.macro",         { fg = p.indigo })
hi("@function.method",        { fg = p.green })
hi("@function.method.call",   { fg = p.green })

hi("@constructor",            { fg = p.yellow })

hi("@operator",               { fg = p.blue })

hi("@keyword",                { fg = p.red })
hi("@keyword.modifier",       { fg = p.red })
hi("@keyword.type",           { fg = p.red })
hi("@keyword.coroutine",      { fg = p.red, italic = true })
hi("@keyword.function",       { fg = p.red })
hi("@keyword.operator",       { fg = p.red })
hi("@keyword.import",         { fg = p.indigo })
hi("@keyword.repeat",         { fg = p.red })
hi("@keyword.return",         { fg = p.red })
hi("@keyword.exception",      { fg = p.red })
hi("@keyword.conditional",    { fg = p.red })
hi("@keyword.conditional.ternary", { fg = p.fg })
hi("@keyword.directive",      { fg = p.indigo })
hi("@keyword.directive.define", { fg = p.indigo })

hi("@punctuation.bracket",    { fg = p.grey })
hi("@punctuation.delimiter",  { fg = p.grey })
hi("@punctuation.special",    { fg = p.indigo })

hi("@comment",                { fg = p.grey, italic = true })
hi("@comment.todo",           { fg = p.bg1, bg = p.yellow, bold = true })
hi("@comment.note",           { fg = p.bg1, bg = p.blue, bold = true })
hi("@comment.warning",        { fg = p.bg1, bg = p.yellow, bold = true })
hi("@comment.error",          { fg = p.bg1, bg = p.red, bold = true })

-- Markup (Markdown, RST, etc.) -----------------------------------------------

hi("@markup.heading",         { fg = p.red, bold = true })
hi("@markup.heading.1",       { fg = p.red, bold = true })
hi("@markup.heading.2",       { fg = p.blue, bold = true })
hi("@markup.heading.3",       { fg = p.yellow, bold = true })
hi("@markup.heading.4",       { fg = p.green, bold = true })
hi("@markup.heading.5",       { fg = p.purple, bold = true })
hi("@markup.heading.6",       { fg = p.indigo, bold = true })
hi("@markup.strong",          { bold = true })
hi("@markup.italic",          { italic = true })
hi("@markup.strikethrough",   { strikethrough = true })
hi("@markup.link",            { fg = p.blue, underline = true })
hi("@markup.link.url",        { fg = p.blue, underline = true })
hi("@markup.link.label",      { fg = p.purple })
hi("@markup.raw",             { fg = p.green })
hi("@markup.raw.block",       { fg = p.green })
hi("@markup.list",            { fg = p.red })
hi("@markup.list.checked",    { fg = p.green })
hi("@markup.list.unchecked",  { fg = p.grey })
hi("@markup.quote",           { fg = p.grey, italic = true })
hi("@markup.math",            { fg = p.purple })

-- HTML/JSX/XML ---------------------------------------------------------------

hi("@tag",                    { fg = p.red })
hi("@tag.builtin",            { fg = p.red })
hi("@tag.attribute",          { fg = p.yellow })
hi("@tag.delimiter",          { fg = p.fg_dim })

-- Language-specific overrides ------------------------------------------------

-- C / C++
hi("@keyword.directive.c",       { fg = p.indigo })
hi("@keyword.directive.cpp",     { fg = p.indigo })
hi("@keyword.directive.define.c",   { fg = p.indigo })
hi("@keyword.directive.define.cpp", { fg = p.indigo })
hi("@type.c",                    { fg = p.yellow })
hi("@type.cpp",                  { fg = p.yellow })
hi("@type.builtin.c",            { fg = p.yellow })
hi("@type.builtin.cpp",          { fg = p.yellow })
hi("@type.qualifier.c",          { fg = p.red })
hi("@type.qualifier.cpp",        { fg = p.red })
hi("@constant.macro.c",          { fg = p.purple })
hi("@constant.macro.cpp",        { fg = p.purple })
hi("@function.macro.c",          { fg = p.indigo })
hi("@function.macro.cpp",        { fg = p.indigo })

-- Assembly (x86, ARM, RISC-V — via tree-sitter-asm / nasm / gas)
hi("@keyword.asm",               { fg = p.red })
hi("@function.builtin.asm",      { fg = p.red })
hi("@label.asm",                 { fg = p.blue })
hi("@variable.builtin.asm",      { fg = p.yellow })
hi("@keyword.directive.asm",     { fg = p.indigo })
hi("@number.asm",                { fg = p.purple })
hi("@string.asm",                { fg = p.green })

hi("@keyword.nasm",              { fg = p.red })
hi("@label.nasm",                { fg = p.blue })
hi("@variable.builtin.nasm",     { fg = p.yellow })
hi("@keyword.directive.nasm",    { fg = p.indigo })

-- Python
hi("@keyword.python",            { fg = p.red })
hi("@keyword.import.python",     { fg = p.indigo })
hi("@keyword.function.python",   { fg = p.red })
hi("@keyword.return.python",     { fg = p.red })
hi("@variable.builtin.python",   { fg = p.purple })
hi("@attribute.python",          { fg = p.indigo })
hi("@string.special.python",     { fg = p.indigo })

-- Rust
hi("@keyword.rust",              { fg = p.red })
hi("@keyword.import.rust",       { fg = p.indigo })
hi("@keyword.modifier.rust",     { fg = p.red })
hi("@keyword.type.rust",         { fg = p.red })
hi("@type.qualifier.rust",       { fg = p.red })
hi("@function.macro.rust",       { fg = p.indigo })
hi("@variable.builtin.rust",     { fg = p.purple })
hi("@attribute.rust",            { fg = p.indigo })

-- Go
hi("@keyword.go",                { fg = p.red })
hi("@keyword.import.go",         { fg = p.indigo })
hi("@keyword.function.go",       { fg = p.red })
hi("@keyword.type.go",           { fg = p.red })
hi("@type.builtin.go",           { fg = p.yellow })

-- JavaScript / TypeScript
hi("@keyword.javascript",        { fg = p.red })
hi("@keyword.typescript",        { fg = p.red })
hi("@keyword.import.javascript", { fg = p.indigo })
hi("@keyword.import.typescript", { fg = p.indigo })
hi("@keyword.import.tsx",        { fg = p.indigo })
hi("@keyword.function.javascript", { fg = p.red })
hi("@keyword.function.typescript", { fg = p.red })
hi("@constructor.javascript",    { fg = p.yellow })
hi("@constructor.typescript",    { fg = p.yellow })
hi("@constructor.tsx",           { fg = p.yellow })
hi("@tag.tsx",                   { fg = p.red })
hi("@tag.attribute.tsx",         { fg = p.yellow })
hi("@variable.builtin.javascript", { fg = p.purple })
hi("@variable.builtin.typescript", { fg = p.purple })

-- Lua
hi("@keyword.lua",               { fg = p.red })
hi("@keyword.function.lua",      { fg = p.red })
hi("@keyword.return.lua",        { fg = p.red })
hi("@keyword.repeat.lua",        { fg = p.red })
hi("@keyword.conditional.lua",   { fg = p.red })
hi("@constructor.lua",           { fg = p.fg_dim })
hi("@variable.builtin.lua",      { fg = p.purple })

-- Java / Kotlin / Scala
hi("@keyword.java",              { fg = p.red })
hi("@keyword.import.java",       { fg = p.indigo })
hi("@type.java",                 { fg = p.yellow })
hi("@attribute.java",            { fg = p.indigo })

hi("@keyword.kotlin",            { fg = p.red })
hi("@keyword.import.kotlin",     { fg = p.indigo })
hi("@attribute.kotlin",          { fg = p.indigo })

-- Ruby
hi("@keyword.ruby",              { fg = p.red })
hi("@keyword.function.ruby",     { fg = p.red })
hi("@variable.builtin.ruby",     { fg = p.purple })
hi("@string.special.symbol.ruby", { fg = p.purple })

-- PHP
hi("@keyword.php",               { fg = p.red })
hi("@keyword.import.php",        { fg = p.indigo })
hi("@variable.builtin.php",      { fg = p.purple })

-- C# / .NET
hi("@keyword.c_sharp",           { fg = p.red })
hi("@keyword.import.c_sharp",    { fg = p.indigo })
hi("@type.c_sharp",              { fg = p.yellow })
hi("@attribute.c_sharp",         { fg = p.indigo })

-- Swift
hi("@keyword.swift",             { fg = p.red })
hi("@keyword.import.swift",      { fg = p.indigo })
hi("@attribute.swift",           { fg = p.indigo })

-- Zig
hi("@keyword.zig",               { fg = p.red })
hi("@keyword.import.zig",        { fg = p.indigo })
hi("@type.builtin.zig",          { fg = p.yellow })

-- Shell / Bash
hi("@keyword.bash",              { fg = p.red })
hi("@function.builtin.bash",     { fg = p.blue })
hi("@variable.bash",             { fg = p.fg })
hi("@variable.builtin.bash",     { fg = p.purple })
hi("@punctuation.special.bash",  { fg = p.indigo })

-- YAML
hi("@property.yaml",             { fg = p.red })
hi("@string.yaml",               { fg = p.green })
hi("@boolean.yaml",              { fg = p.purple })
hi("@number.yaml",               { fg = p.purple })

-- TOML
hi("@property.toml",             { fg = p.red })
hi("@type.toml",                 { fg = p.yellow })
hi("@string.toml",               { fg = p.green })

-- JSON / JSONC
hi("@property.json",             { fg = p.red })
hi("@property.jsonc",            { fg = p.red })
hi("@string.json",               { fg = p.green })
hi("@string.jsonc",              { fg = p.green })
hi("@number.json",               { fg = p.purple })
hi("@number.jsonc",              { fg = p.purple })
hi("@boolean.json",              { fg = p.purple })
hi("@boolean.jsonc",             { fg = p.purple })

-- CSS / SCSS
hi("@property.css",              { fg = p.blue })
hi("@property.scss",             { fg = p.blue })
hi("@type.css",                  { fg = p.yellow })
hi("@type.scss",                 { fg = p.yellow })
hi("@string.css",                { fg = p.green })
hi("@string.scss",               { fg = p.green })
hi("@number.css",                { fg = p.purple })
hi("@number.scss",               { fg = p.purple })
hi("@keyword.css",               { fg = p.indigo })
hi("@keyword.scss",              { fg = p.indigo })
hi("@keyword.import.css",        { fg = p.indigo })
hi("@keyword.import.scss",       { fg = p.indigo })
hi("@attribute.css",             { fg = p.indigo })
hi("@attribute.scss",            { fg = p.indigo })
hi("@function.css",              { fg = p.blue })
hi("@function.scss",             { fg = p.blue })

-- SQL
hi("@keyword.sql",               { fg = p.red })
hi("@keyword.operator.sql",      { fg = p.red })
hi("@type.sql",                  { fg = p.yellow })
hi("@function.sql",              { fg = p.blue })
hi("@string.sql",                { fg = p.green })
hi("@number.sql",                { fg = p.purple })

-- Dockerfile
hi("@keyword.dockerfile",        { fg = p.red })
hi("@string.dockerfile",         { fg = p.green })

-- Makefile
hi("@keyword.make",              { fg = p.red })
hi("@function.make",             { fg = p.blue })
hi("@variable.make",             { fg = p.fg })
hi("@string.make",               { fg = p.green })
hi("@operator.make",             { fg = p.fg })

-- Haskell
hi("@keyword.haskell",           { fg = p.red })
hi("@keyword.import.haskell",    { fg = p.indigo })
hi("@keyword.function.haskell",  { fg = p.red })
hi("@keyword.return.haskell",    { fg = p.red })
hi("@type.haskell",              { fg = p.yellow })
hi("@constructor.haskell",       { fg = p.yellow })
hi("@variable.builtin.haskell",  { fg = p.purple })
hi("@operator.haskell",          { fg = p.blue })

-- Elixir
hi("@keyword.elixir",            { fg = p.red })
hi("@keyword.function.elixir",   { fg = p.red })
hi("@keyword.operator.elixir",   { fg = p.red })
hi("@attribute.elixir",          { fg = p.indigo })
hi("@string.special.symbol.elixir", { fg = p.yellow })
hi("@constant.elixir",           { fg = p.yellow })
hi("@module.elixir",             { fg = p.yellow })

-- Erlang
hi("@keyword.erlang",            { fg = p.red })
hi("@keyword.function.erlang",   { fg = p.red })
hi("@type.erlang",               { fg = p.yellow })
hi("@string.special.symbol.erlang", { fg = p.yellow })
hi("@module.erlang",             { fg = p.yellow })

-- Dart / Flutter
hi("@keyword.dart",              { fg = p.red })
hi("@keyword.import.dart",       { fg = p.indigo })
hi("@attribute.dart",            { fg = p.indigo })
hi("@type.dart",                 { fg = p.yellow })

-- Common Lisp / Scheme / Clojure / Fennel / Racket
hi("@function.builtin.commonlisp",  { fg = p.red })
hi("@function.macro.commonlisp",    { fg = p.red, bold = true })
hi("@function.builtin.scheme",      { fg = p.red })
hi("@function.macro.scheme",        { fg = p.red, bold = true })
hi("@function.builtin.clojure",     { fg = p.red })
hi("@function.macro.clojure",       { fg = p.red, bold = true })
hi("@function.builtin.fennel",      { fg = p.red })
hi("@function.macro.fennel",        { fg = p.red, bold = true })
hi("@function.builtin.racket",      { fg = p.red })
hi("@function.macro.racket",        { fg = p.red, bold = true })
hi("@string.special.symbol.commonlisp", { fg = p.yellow })
hi("@string.special.symbol.scheme",     { fg = p.yellow })
hi("@string.special.symbol.clojure",    { fg = p.yellow })
hi("@string.special.symbol.fennel",     { fg = p.yellow })
hi("@string.special.symbol.racket",     { fg = p.yellow })

-- OCaml / F# / ReasonML / ReScript
hi("@keyword.ocaml",             { fg = p.red })
hi("@keyword.import.ocaml",      { fg = p.indigo })
hi("@keyword.function.ocaml",    { fg = p.red })
hi("@keyword.return.ocaml",      { fg = p.red })
hi("@type.ocaml",                { fg = p.yellow })
hi("@constructor.ocaml",         { fg = p.yellow })
hi("@module.ocaml",              { fg = p.yellow })
hi("@attribute.ocaml",           { fg = p.indigo })

hi("@keyword.fsharp",            { fg = p.red })
hi("@keyword.import.fsharp",     { fg = p.indigo })
hi("@type.fsharp",               { fg = p.yellow })
hi("@constructor.fsharp",        { fg = p.yellow })
hi("@attribute.fsharp",          { fg = p.indigo })

-- Scala
hi("@keyword.scala",             { fg = p.red })
hi("@keyword.import.scala",      { fg = p.indigo })
hi("@keyword.function.scala",    { fg = p.red })
hi("@keyword.type.scala",        { fg = p.red })
hi("@type.scala",                { fg = p.yellow })
hi("@attribute.scala",           { fg = p.indigo })

-- Groovy
hi("@keyword.groovy",            { fg = p.red })
hi("@keyword.import.groovy",     { fg = p.indigo })
hi("@attribute.groovy",          { fg = p.indigo })

-- Perl
hi("@keyword.perl",              { fg = p.red })
hi("@keyword.import.perl",       { fg = p.indigo })
hi("@variable.builtin.perl",     { fg = p.purple })
hi("@variable.perl",             { fg = p.fg })
hi("@string.regex.perl",         { fg = p.indigo })

-- R
hi("@keyword.r",                 { fg = p.red })
hi("@keyword.function.r",        { fg = p.red })
hi("@keyword.return.r",          { fg = p.red })
hi("@variable.builtin.r",        { fg = p.purple })
hi("@function.builtin.r",        { fg = p.green })
hi("@boolean.r",                 { fg = p.purple, bold = true })
hi("@operator.r",                { fg = p.blue })

-- Julia
hi("@keyword.julia",             { fg = p.red })
hi("@keyword.import.julia",      { fg = p.indigo })
hi("@keyword.function.julia",    { fg = p.red })
hi("@keyword.return.julia",      { fg = p.red })
hi("@keyword.type.julia",        { fg = p.red })
hi("@type.julia",                { fg = p.yellow })
hi("@type.builtin.julia",        { fg = p.yellow })
hi("@constant.julia",            { fg = p.yellow })
hi("@variable.builtin.julia",    { fg = p.purple })
hi("@attribute.julia",           { fg = p.indigo })

-- Nim
hi("@keyword.nim",               { fg = p.red })
hi("@keyword.import.nim",        { fg = p.indigo })
hi("@keyword.function.nim",      { fg = p.red })
hi("@keyword.type.nim",          { fg = p.red })
hi("@type.nim",                  { fg = p.yellow })
hi("@attribute.nim",             { fg = p.indigo })

-- V (Vlang)
hi("@keyword.v",                 { fg = p.red })
hi("@keyword.import.v",          { fg = p.indigo })
hi("@keyword.function.v",        { fg = p.red })
hi("@type.v",                    { fg = p.yellow })
hi("@attribute.v",               { fg = p.indigo })

-- Odin
hi("@keyword.odin",              { fg = p.red })
hi("@keyword.import.odin",       { fg = p.indigo })
hi("@keyword.type.odin",         { fg = p.red })
hi("@type.odin",                 { fg = p.yellow })
hi("@type.builtin.odin",         { fg = p.yellow })
hi("@attribute.odin",            { fg = p.indigo })

-- Gleam
hi("@keyword.gleam",             { fg = p.red })
hi("@keyword.import.gleam",      { fg = p.indigo })
hi("@keyword.function.gleam",    { fg = p.red })
hi("@type.gleam",                { fg = p.yellow })
hi("@constructor.gleam",         { fg = p.yellow })
hi("@module.gleam",              { fg = p.yellow })

-- Elm / PureScript
hi("@keyword.elm",               { fg = p.red })
hi("@keyword.import.elm",        { fg = p.indigo })
hi("@type.elm",                  { fg = p.yellow })
hi("@constructor.elm",           { fg = p.yellow })
hi("@module.elm",                { fg = p.yellow })

hi("@keyword.purescript",        { fg = p.red })
hi("@keyword.import.purescript", { fg = p.indigo })
hi("@type.purescript",           { fg = p.yellow })
hi("@constructor.purescript",    { fg = p.yellow })
hi("@module.purescript",         { fg = p.yellow })

-- Objective-C / Objective-C++
hi("@keyword.objc",              { fg = p.red })
hi("@keyword.directive.objc",    { fg = p.indigo })
hi("@keyword.import.objc",       { fg = p.indigo })
hi("@type.objc",                 { fg = p.yellow })
hi("@type.qualifier.objc",       { fg = p.red })
hi("@attribute.objc",            { fg = p.indigo })
hi("@string.special.objc",       { fg = p.green })

-- CUDA
hi("@keyword.cuda",              { fg = p.red })
hi("@keyword.directive.cuda",    { fg = p.indigo })
hi("@type.cuda",                 { fg = p.yellow })
hi("@type.qualifier.cuda",       { fg = p.red })
hi("@function.macro.cuda",       { fg = p.indigo })

-- Shader languages (GLSL / HLSL / WGSL)
hi("@keyword.glsl",              { fg = p.red })
hi("@type.glsl",                 { fg = p.yellow })
hi("@type.builtin.glsl",         { fg = p.yellow })
hi("@type.qualifier.glsl",       { fg = p.red })
hi("@keyword.directive.glsl",    { fg = p.indigo })
hi("@variable.builtin.glsl",     { fg = p.purple })

hi("@keyword.hlsl",              { fg = p.red })
hi("@type.hlsl",                 { fg = p.yellow })
hi("@type.builtin.hlsl",         { fg = p.yellow })
hi("@keyword.directive.hlsl",    { fg = p.indigo })

hi("@keyword.wgsl",              { fg = p.red })
hi("@type.wgsl",                 { fg = p.yellow })
hi("@type.builtin.wgsl",         { fg = p.yellow })
hi("@attribute.wgsl",            { fg = p.indigo })

-- Fortran
hi("@keyword.fortran",           { fg = p.red })
hi("@keyword.import.fortran",    { fg = p.indigo })
hi("@keyword.type.fortran",      { fg = p.red })
hi("@type.fortran",              { fg = p.yellow })
hi("@type.builtin.fortran",      { fg = p.yellow })

-- Pascal / Delphi
hi("@keyword.pascal",            { fg = p.red })
hi("@keyword.function.pascal",   { fg = p.red })
hi("@keyword.type.pascal",       { fg = p.red })
hi("@type.pascal",               { fg = p.yellow })
hi("@keyword.import.pascal",     { fg = p.indigo })

-- Ada
hi("@keyword.ada",               { fg = p.red })
hi("@keyword.import.ada",        { fg = p.indigo })
hi("@keyword.function.ada",      { fg = p.red })
hi("@keyword.type.ada",          { fg = p.red })
hi("@type.ada",                  { fg = p.yellow })
hi("@attribute.ada",             { fg = p.indigo })

-- Prolog
hi("@keyword.prolog",            { fg = p.red })
hi("@function.prolog",           { fg = p.green })
hi("@variable.prolog",           { fg = p.fg })
hi("@operator.prolog",           { fg = p.blue })

-- Verilog / SystemVerilog / VHDL
hi("@keyword.verilog",           { fg = p.red })
hi("@keyword.type.verilog",      { fg = p.red })
hi("@type.verilog",              { fg = p.yellow })
hi("@type.builtin.verilog",      { fg = p.yellow })
hi("@keyword.directive.verilog", { fg = p.indigo })
hi("@constant.verilog",          { fg = p.yellow })

hi("@keyword.vhdl",              { fg = p.red })
hi("@keyword.type.vhdl",         { fg = p.red })
hi("@type.vhdl",                 { fg = p.yellow })
hi("@type.builtin.vhdl",         { fg = p.yellow })

-- Solidity
hi("@keyword.solidity",          { fg = p.red })
hi("@keyword.import.solidity",   { fg = p.indigo })
hi("@keyword.type.solidity",     { fg = p.red })
hi("@type.solidity",             { fg = p.yellow })
hi("@type.builtin.solidity",     { fg = p.yellow })
hi("@attribute.solidity",        { fg = p.indigo })
hi("@variable.builtin.solidity", { fg = p.purple })

-- Nix
hi("@keyword.nix",               { fg = p.red })
hi("@keyword.import.nix",        { fg = p.indigo })
hi("@keyword.conditional.nix",   { fg = p.red })
hi("@function.builtin.nix",      { fg = p.green })
hi("@variable.builtin.nix",      { fg = p.purple })
hi("@punctuation.special.nix",   { fg = p.indigo })

-- Terraform / HCL
hi("@keyword.hcl",               { fg = p.red })
hi("@type.hcl",                  { fg = p.yellow })
hi("@property.hcl",              { fg = p.purple })
hi("@string.hcl",                { fg = p.green })
hi("@number.hcl",                { fg = p.purple })
hi("@boolean.hcl",               { fg = p.purple, bold = true })

-- GraphQL
hi("@keyword.graphql",           { fg = p.red })
hi("@type.graphql",              { fg = p.yellow })
hi("@property.graphql",          { fg = p.purple })
hi("@variable.graphql",          { fg = p.blue })
hi("@constant.graphql",          { fg = p.yellow })

-- Protobuf
hi("@keyword.proto",             { fg = p.red })
hi("@keyword.import.proto",      { fg = p.indigo })
hi("@type.proto",                { fg = p.yellow })
hi("@type.builtin.proto",        { fg = p.yellow })
hi("@property.proto",            { fg = p.purple })
hi("@number.proto",              { fg = p.purple })

-- LaTeX / TeX
hi("@keyword.latex",             { fg = p.red })
hi("@function.latex",            { fg = p.green })
hi("@function.macro.latex",      { fg = p.indigo })
hi("@markup.heading.latex",      { fg = p.red, bold = true })
hi("@markup.environment.latex",  { fg = p.indigo })
hi("@markup.environment.name.latex", { fg = p.yellow })
hi("@markup.math.latex",         { fg = p.purple })
hi("@markup.raw.latex",          { fg = p.green })
hi("@punctuation.special.latex", { fg = p.indigo })
hi("@module.latex",              { fg = p.yellow })

-- BibTeX / BibLaTeX
hi("@keyword.bibtex",            { fg = p.red })
hi("@type.bibtex",               { fg = p.yellow })
hi("@property.bibtex",           { fg = p.purple })
hi("@string.bibtex",             { fg = p.green })
hi("@number.bibtex",             { fg = p.purple })
hi("@label.bibtex",              { fg = p.blue })
hi("@punctuation.special.bibtex", { fg = p.indigo })

-- TeX (plain)
hi("@keyword.tex",               { fg = p.red })
hi("@function.tex",              { fg = p.green })
hi("@function.macro.tex",        { fg = p.indigo })
hi("@punctuation.special.tex",   { fg = p.indigo })
hi("@markup.math.tex",           { fg = p.purple })

-- ConTeXt
hi("@keyword.context",           { fg = p.red })
hi("@function.context",          { fg = p.green })
hi("@function.macro.context",    { fg = p.indigo })
hi("@markup.heading.context",    { fg = p.red, bold = true })
hi("@markup.environment.context",      { fg = p.indigo })
hi("@markup.environment.name.context", { fg = p.yellow })

-- Typst
hi("@keyword.typst",             { fg = p.red })
hi("@keyword.import.typst",      { fg = p.indigo })
hi("@function.typst",            { fg = p.green })
hi("@function.builtin.typst",    { fg = p.green })
hi("@type.typst",                { fg = p.yellow })
hi("@markup.heading.typst",      { fg = p.red, bold = true })
hi("@markup.heading.1.typst",    { fg = p.red, bold = true })
hi("@markup.heading.2.typst",    { fg = p.blue, bold = true })
hi("@markup.heading.3.typst",    { fg = p.yellow, bold = true })
hi("@markup.strong.typst",       { bold = true })
hi("@markup.italic.typst",       { italic = true })
hi("@markup.raw.typst",          { fg = p.green })
hi("@markup.raw.block.typst",    { fg = p.green })
hi("@markup.math.typst",         { fg = p.purple })
hi("@markup.link.typst",         { fg = p.blue, underline = true })
hi("@markup.link.url.typst",     { fg = p.blue, underline = true })
hi("@markup.link.label.typst",   { fg = p.purple })
hi("@markup.list.typst",         { fg = p.red })
hi("@punctuation.special.typst", { fg = p.indigo })
hi("@label.typst",               { fg = p.blue })
hi("@module.typst",              { fg = p.yellow })

-- CMake
hi("@keyword.cmake",             { fg = p.red })
hi("@function.cmake",            { fg = p.green })
hi("@function.builtin.cmake",    { fg = p.green })
hi("@variable.cmake",            { fg = p.fg })
hi("@variable.builtin.cmake",    { fg = p.purple })
hi("@constant.cmake",            { fg = p.yellow })

-- Meson
hi("@keyword.meson",             { fg = p.red })
hi("@function.meson",            { fg = p.green })
hi("@function.builtin.meson",    { fg = p.green })
hi("@string.meson",              { fg = p.green })
hi("@boolean.meson",             { fg = p.purple, bold = true })

-- Fish shell
hi("@keyword.fish",              { fg = p.red })
hi("@function.fish",             { fg = p.green })
hi("@function.builtin.fish",     { fg = p.green })
hi("@variable.fish",             { fg = p.fg })
hi("@variable.builtin.fish",     { fg = p.purple })
hi("@operator.fish",             { fg = p.blue })

-- PowerShell
hi("@keyword.powershell",        { fg = p.red })
hi("@function.powershell",       { fg = p.green })
hi("@variable.powershell",       { fg = p.fg })
hi("@variable.builtin.powershell", { fg = p.purple })
hi("@type.powershell",           { fg = p.yellow })
hi("@operator.powershell",       { fg = p.blue })

-- Lua-based configs (Luau / Teal)
hi("@keyword.luau",              { fg = p.red })
hi("@type.luau",                 { fg = p.yellow })
hi("@type.builtin.luau",         { fg = p.yellow })

hi("@keyword.teal",              { fg = p.red })
hi("@type.teal",                 { fg = p.yellow })

-- Svelte / Vue / Astro (web frameworks)
hi("@tag.svelte",                { fg = p.red })
hi("@tag.attribute.svelte",      { fg = p.yellow })
hi("@keyword.svelte",            { fg = p.red })
hi("@punctuation.special.svelte", { fg = p.indigo })

hi("@tag.vue",                   { fg = p.red })
hi("@tag.attribute.vue",         { fg = p.yellow })
hi("@keyword.vue",               { fg = p.red })

hi("@tag.astro",                 { fg = p.red })
hi("@tag.attribute.astro",       { fg = p.yellow })
hi("@keyword.astro",             { fg = p.red })

-- XML
hi("@tag.xml",                   { fg = p.red })
hi("@tag.attribute.xml",         { fg = p.yellow })
hi("@tag.delimiter.xml",         { fg = p.grey })
hi("@string.xml",                { fg = p.green })

-- Regex
hi("@string.regex",              { fg = p.indigo })
hi("@punctuation.bracket.regex", { fg = p.blue })
hi("@operator.regex",            { fg = p.blue })
hi("@character.special.regex",   { fg = p.red })
hi("@constant.regex",            { fg = p.purple })

-- INI / conf / properties / editorconfig
hi("@property.ini",              { fg = p.red })
hi("@string.ini",                { fg = p.green })
hi("@type.ini",                  { fg = p.yellow })

-- Nginx / Apache
hi("@keyword.nginx",             { fg = p.red })
hi("@property.nginx",            { fg = p.purple })
hi("@string.nginx",              { fg = p.green })
hi("@number.nginx",              { fg = p.purple })

-- WASM text format (WAT)
hi("@keyword.wat",               { fg = p.red })
hi("@type.wat",                  { fg = p.yellow })
hi("@variable.builtin.wat",      { fg = p.purple })
hi("@number.wat",                { fg = p.purple })
hi("@string.wat",                { fg = p.green })

-- Awk
hi("@keyword.awk",               { fg = p.red })
hi("@function.builtin.awk",      { fg = p.green })
hi("@variable.builtin.awk",      { fg = p.purple })
hi("@string.awk",                { fg = p.green })
hi("@string.regex.awk",          { fg = p.indigo })

-- Tcl
hi("@keyword.tcl",               { fg = p.red })
hi("@function.builtin.tcl",      { fg = p.green })
hi("@variable.tcl",              { fg = p.fg })

-- Vimdoc / Help
hi("@label.vimdoc",              { fg = p.yellow, bold = true })
hi("@markup.heading.vimdoc",     { fg = p.red, bold = true })
hi("@markup.link.vimdoc",        { fg = p.blue, underline = true })
hi("@markup.raw.vimdoc",         { fg = p.green })
hi("@variable.vimdoc",           { fg = p.purple })

-- Vim script
hi("@keyword.vim",               { fg = p.red })
hi("@function.vim",              { fg = p.green })
hi("@function.builtin.vim",      { fg = p.green })
hi("@variable.vim",              { fg = p.fg })
hi("@variable.builtin.vim",      { fg = p.purple })
hi("@keyword.import.vim",        { fg = p.indigo })

-- Git-related
hi("@keyword.gitcommit",         { fg = p.red })
hi("@string.gitcommit",          { fg = p.green })
hi("@markup.heading.gitcommit",  { fg = p.yellow, bold = true })
hi("@keyword.gitrebase",         { fg = p.red })
hi("@constant.gitrebase",        { fg = p.purple })
hi("@number.gitrebase",          { fg = p.yellow })

-- Diff (expanded)
hi("@text.diff.add",             { fg = p.green })
hi("@text.diff.delete",          { fg = p.red })
hi("@attribute.diff",            { fg = p.indigo })

-- Kubernetes / Helm (YAML-based, keys follow YAML pattern)
hi("@property.helm",             { fg = p.red })
hi("@string.helm",               { fg = p.green })
hi("@punctuation.special.helm",  { fg = p.indigo })
hi("@function.helm",             { fg = p.green })

-- Jsonnet / Pkl / Cue (config languages)
hi("@keyword.jsonnet",           { fg = p.red })
hi("@function.jsonnet",          { fg = p.green })
hi("@variable.builtin.jsonnet",  { fg = p.purple })
hi("@string.jsonnet",            { fg = p.green })
hi("@number.jsonnet",            { fg = p.purple })

hi("@keyword.pkl",               { fg = p.red })
hi("@keyword.import.pkl",        { fg = p.indigo })
hi("@type.pkl",                  { fg = p.yellow })
hi("@property.pkl",              { fg = p.purple })

hi("@keyword.cue",               { fg = p.red })
hi("@type.cue",                  { fg = p.yellow })
hi("@property.cue",              { fg = p.purple })
hi("@string.cue",                { fg = p.green })

-- Starlark / Bazel (BUILD, .bzl)
hi("@keyword.starlark",          { fg = p.red })
hi("@function.starlark",         { fg = p.green })
hi("@function.builtin.starlark", { fg = p.green })
hi("@string.starlark",           { fg = p.green })
hi("@variable.builtin.starlark", { fg = p.purple })

-- Just (justfile)
hi("@keyword.just",              { fg = p.red })
hi("@function.just",             { fg = p.green })
hi("@variable.just",             { fg = p.fg })
hi("@string.just",               { fg = p.green })
hi("@operator.just",             { fg = p.blue })

-- LESS
hi("@property.less",             { fg = p.blue })
hi("@type.less",                 { fg = p.yellow })
hi("@string.less",               { fg = p.green })
hi("@number.less",               { fg = p.purple })
hi("@keyword.less",              { fg = p.indigo })
hi("@keyword.import.less",       { fg = p.indigo })
hi("@function.less",             { fg = p.blue })

-- Stylus
hi("@property.stylus",           { fg = p.blue })
hi("@type.stylus",               { fg = p.yellow })
hi("@string.stylus",             { fg = p.green })
hi("@number.stylus",             { fg = p.purple })
hi("@keyword.stylus",            { fg = p.indigo })

-- Pug / Jade
hi("@tag.pug",                   { fg = p.red })
hi("@tag.attribute.pug",         { fg = p.yellow })
hi("@string.pug",                { fg = p.green })
hi("@keyword.pug",               { fg = p.red })
hi("@punctuation.special.pug",   { fg = p.indigo })

-- EJS / ERB (embedded templates)
hi("@keyword.embedded_template", { fg = p.red })
hi("@punctuation.special.embedded_template", { fg = p.indigo })

-- Jinja / Jinja2 / Twig
hi("@keyword.jinja",             { fg = p.red })
hi("@function.jinja",            { fg = p.green })
hi("@variable.jinja",            { fg = p.fg })
hi("@punctuation.special.jinja", { fg = p.indigo })

-- Handlebars / Mustache
hi("@keyword.glimmer",           { fg = p.red })
hi("@variable.glimmer",          { fg = p.fg })
hi("@tag.glimmer",               { fg = p.red })
hi("@punctuation.special.glimmer", { fg = p.indigo })

-- SQL dialects (PostgreSQL, MySQL, SQLite)
hi("@keyword.plpgsql",           { fg = p.red })
hi("@type.plpgsql",              { fg = p.yellow })
hi("@function.plpgsql",          { fg = p.green })

-- Prisma (ORM schema)
hi("@keyword.prisma",            { fg = p.red })
hi("@type.prisma",               { fg = p.yellow })
hi("@type.builtin.prisma",       { fg = p.yellow })
hi("@property.prisma",           { fg = p.purple })
hi("@attribute.prisma",          { fg = p.indigo })
hi("@string.prisma",             { fg = p.green })

-- D
hi("@keyword.d",                 { fg = p.red })
hi("@keyword.import.d",          { fg = p.indigo })
hi("@keyword.type.d",            { fg = p.red })
hi("@type.d",                    { fg = p.yellow })
hi("@type.builtin.d",            { fg = p.yellow })
hi("@attribute.d",               { fg = p.indigo })
hi("@function.macro.d",          { fg = p.indigo })

-- Crystal
hi("@keyword.crystal",           { fg = p.red })
hi("@keyword.function.crystal",  { fg = p.red })
hi("@keyword.import.crystal",    { fg = p.indigo })
hi("@type.crystal",              { fg = p.yellow })
hi("@variable.builtin.crystal",  { fg = p.purple })
hi("@string.special.symbol.crystal", { fg = p.yellow })
hi("@attribute.crystal",         { fg = p.indigo })

-- Hack / HHVM
hi("@keyword.hack",              { fg = p.red })
hi("@keyword.import.hack",       { fg = p.indigo })
hi("@type.hack",                 { fg = p.yellow })
hi("@attribute.hack",            { fg = p.indigo })
hi("@variable.builtin.hack",     { fg = p.purple })

-- Raku (Perl 6)
hi("@keyword.raku",              { fg = p.red })
hi("@keyword.import.raku",       { fg = p.indigo })
hi("@variable.builtin.raku",     { fg = p.purple })
hi("@string.regex.raku",         { fg = p.indigo })
hi("@type.raku",                 { fg = p.yellow })

-- Matlab / Octave
hi("@keyword.matlab",            { fg = p.red })
hi("@keyword.function.matlab",   { fg = p.red })
hi("@keyword.return.matlab",     { fg = p.red })
hi("@function.builtin.matlab",   { fg = p.green })
hi("@variable.builtin.matlab",   { fg = p.purple })
hi("@operator.matlab",           { fg = p.blue })

-- Lean 4 / Coq / Agda / Idris (proof assistants)
hi("@keyword.lean",              { fg = p.red })
hi("@keyword.import.lean",       { fg = p.indigo })
hi("@type.lean",                 { fg = p.yellow })
hi("@constructor.lean",          { fg = p.yellow })
hi("@attribute.lean",            { fg = p.indigo })

hi("@keyword.coq",               { fg = p.red })
hi("@type.coq",                  { fg = p.yellow })
hi("@constructor.coq",           { fg = p.yellow })

hi("@keyword.agda",              { fg = p.red })
hi("@keyword.import.agda",       { fg = p.indigo })
hi("@type.agda",                 { fg = p.yellow })

hi("@keyword.idris",             { fg = p.red })
hi("@keyword.import.idris",      { fg = p.indigo })
hi("@type.idris",                { fg = p.yellow })
hi("@constructor.idris",         { fg = p.yellow })

-- Dhall
hi("@keyword.dhall",             { fg = p.red })
hi("@keyword.import.dhall",      { fg = p.indigo })
hi("@type.dhall",                { fg = p.yellow })
hi("@type.builtin.dhall",        { fg = p.yellow })
hi("@operator.dhall",            { fg = p.blue })

-- Zig-adjacent (C3, Carbon)
hi("@keyword.c3",                { fg = p.red })
hi("@type.c3",                   { fg = p.yellow })
hi("@attribute.c3",              { fg = p.indigo })

-- Move (blockchain)
hi("@keyword.move",              { fg = p.red })
hi("@keyword.import.move",       { fg = p.indigo })
hi("@type.move",                 { fg = p.yellow })
hi("@attribute.move",            { fg = p.indigo })
hi("@variable.builtin.move",     { fg = p.purple })

-- Cairo (blockchain/Starknet)
hi("@keyword.cairo",             { fg = p.red })
hi("@keyword.import.cairo",      { fg = p.indigo })
hi("@type.cairo",                { fg = p.yellow })
hi("@attribute.cairo",           { fg = p.indigo })
hi("@function.macro.cairo",      { fg = p.indigo })

-- Yul (EVM inline assembly)
hi("@keyword.yul",               { fg = p.red })
hi("@function.builtin.yul",      { fg = p.red })
hi("@number.yul",                { fg = p.purple })

-- Earthfile
hi("@keyword.earthfile",         { fg = p.red })
hi("@function.earthfile",        { fg = p.green })
hi("@string.earthfile",          { fg = p.green })

-- SSH config
hi("@property.ssh_config",       { fg = p.red })
hi("@string.ssh_config",         { fg = p.green })
hi("@number.ssh_config",         { fg = p.purple })
hi("@boolean.ssh_config",        { fg = p.purple, bold = true })

-- systemd unit files
hi("@property.systemd",          { fg = p.red })
hi("@type.systemd",              { fg = p.yellow })
hi("@string.systemd",            { fg = p.green })
hi("@boolean.systemd",           { fg = p.purple, bold = true })

-- dotenv (.env)
hi("@property.dotenv",           { fg = p.red })
hi("@string.dotenv",             { fg = p.green })
hi("@number.dotenv",             { fg = p.purple })

-- EditorConfig
hi("@property.editorconfig",     { fg = p.red })
hi("@string.editorconfig",       { fg = p.green })
hi("@boolean.editorconfig",      { fg = p.purple, bold = true })

-- gitignore / gitattributes
hi("@string.special.path.gitignore",     { fg = p.green })
hi("@operator.gitignore",                { fg = p.blue })
hi("@property.gitattributes",            { fg = p.red })
hi("@string.gitattributes",              { fg = p.green })

-- robots.txt
hi("@keyword.robots",            { fg = p.red })
hi("@string.robots",             { fg = p.green })

-- CSV / TSV (basic)
hi("@number.csv",                { fg = p.purple })
hi("@string.csv",                { fg = p.green })

-- Markdown / MDX (language-specific)
hi("@markup.heading.1.markdown",          { fg = p.red, bold = true })
hi("@markup.heading.2.markdown",          { fg = p.blue, bold = true })
hi("@markup.heading.3.markdown",          { fg = p.yellow, bold = true })
hi("@markup.heading.4.markdown",          { fg = p.green, bold = true })
hi("@markup.heading.5.markdown",          { fg = p.purple, bold = true })
hi("@markup.heading.6.markdown",          { fg = p.indigo, bold = true })
hi("@markup.heading.1.markdown_inline",   { fg = p.red, bold = true })
hi("@markup.heading.2.markdown_inline",   { fg = p.blue, bold = true })
hi("@markup.heading.3.markdown_inline",   { fg = p.yellow, bold = true })
hi("@label.markdown",                     { fg = p.blue })

hi("@keyword.mdx",               { fg = p.red })
hi("@tag.mdx",                   { fg = p.red })
hi("@tag.attribute.mdx",         { fg = p.yellow })
hi("@tag.delimiter.mdx",         { fg = p.grey })

-- RST (reStructuredText)
hi("@markup.heading.rst",        { fg = p.red, bold = true })
hi("@markup.link.rst",           { fg = p.blue, underline = true })
hi("@markup.link.label.rst",     { fg = p.purple })
hi("@markup.raw.rst",            { fg = p.green })
hi("@markup.raw.block.rst",      { fg = p.green })
hi("@markup.italic.rst",         { italic = true })
hi("@markup.strong.rst",         { bold = true })
hi("@keyword.directive.rst",     { fg = p.indigo })
hi("@label.rst",                 { fg = p.blue })

-- AsciiDoc
hi("@markup.heading.asciidoc",   { fg = p.red, bold = true })
hi("@markup.heading.1.asciidoc", { fg = p.red, bold = true })
hi("@markup.heading.2.asciidoc", { fg = p.blue, bold = true })
hi("@markup.heading.3.asciidoc", { fg = p.yellow, bold = true })
hi("@markup.link.asciidoc",      { fg = p.blue, underline = true })
hi("@markup.raw.asciidoc",       { fg = p.green })
hi("@markup.strong.asciidoc",    { bold = true })
hi("@markup.italic.asciidoc",    { italic = true })
hi("@keyword.directive.asciidoc", { fg = p.indigo })
hi("@label.asciidoc",            { fg = p.blue })

-- Org mode
hi("@markup.heading.org",        { fg = p.red, bold = true })
hi("@markup.heading.1.org",      { fg = p.red, bold = true })
hi("@markup.heading.2.org",      { fg = p.blue, bold = true })
hi("@markup.heading.3.org",      { fg = p.yellow, bold = true })
hi("@markup.heading.4.org",      { fg = p.green, bold = true })
hi("@markup.heading.5.org",      { fg = p.purple, bold = true })
hi("@markup.heading.6.org",      { fg = p.indigo, bold = true })
hi("@markup.link.org",           { fg = p.blue, underline = true })
hi("@markup.link.url.org",       { fg = p.blue, underline = true })
hi("@markup.raw.org",            { fg = p.green })
hi("@markup.raw.block.org",      { fg = p.green })
hi("@markup.strong.org",         { bold = true })
hi("@markup.italic.org",         { italic = true })
hi("@markup.list.org",           { fg = p.red })
hi("@markup.list.checked.org",   { fg = p.green })
hi("@markup.list.unchecked.org", { fg = p.grey })
hi("@keyword.org",               { fg = p.indigo })
hi("@property.org",              { fg = p.purple })
hi("@markup.math.org",           { fg = p.purple })
hi("@label.org",                 { fg = p.yellow })

-- Textile
hi("@markup.heading.textile",    { fg = p.red, bold = true })
hi("@markup.link.textile",       { fg = p.blue, underline = true })
hi("@markup.raw.textile",        { fg = p.green })
hi("@markup.strong.textile",     { bold = true })
hi("@markup.italic.textile",     { italic = true })

-- Djot
hi("@markup.heading.djot",       { fg = p.red, bold = true })
hi("@markup.heading.1.djot",     { fg = p.red, bold = true })
hi("@markup.heading.2.djot",     { fg = p.blue, bold = true })
hi("@markup.heading.3.djot",     { fg = p.yellow, bold = true })
hi("@markup.link.djot",          { fg = p.blue, underline = true })
hi("@markup.raw.djot",           { fg = p.green })
hi("@markup.strong.djot",        { bold = true })
hi("@markup.italic.djot",        { italic = true })
hi("@markup.math.djot",          { fg = p.purple })

-- Markdown-inline (extra)
hi("@markup.link.label.markdown_inline",    { fg = p.blue })
hi("@markup.link.url.markdown_inline",      { fg = p.purple, underline = true })
hi("@markup.raw.markdown_inline",           { fg = p.green })
hi("@punctuation.special.markdown",         { fg = p.grey })
hi("@punctuation.special.markdown_inline",  { fg = p.grey })

-- HTTP (rest.nvim / kulala style)
hi("@keyword.http",              { fg = p.red })
hi("@string.http",               { fg = p.green })
hi("@variable.http",             { fg = p.blue })
hi("@number.http",               { fg = p.purple })
hi("@constant.http",             { fg = p.yellow })

-- Luadoc / EmmyLua / LDoc annotations
hi("@keyword.luadoc",            { fg = p.indigo })
hi("@type.luadoc",               { fg = p.yellow })
hi("@variable.luadoc",           { fg = p.blue })

-- JSDoc / TSDoc / JavaDoc
hi("@keyword.jsdoc",             { fg = p.indigo })
hi("@type.jsdoc",                { fg = p.yellow })
hi("@variable.jsdoc",            { fg = p.blue })

-- Doxygen (C/C++ doc comments)
hi("@keyword.doxygen",           { fg = p.indigo })
hi("@type.doxygen",              { fg = p.yellow })
hi("@variable.doxygen",          { fg = p.blue })

-- Rainbow parentheses (for ts-rainbow / rainbow-delimiters.nvim)
hi("RainbowDelimiterRed",     { fg = p.red })
hi("RainbowDelimiterYellow",  { fg = p.yellow })
hi("RainbowDelimiterBlue",    { fg = p.blue })
hi("RainbowDelimiterOrange",  { fg = p.green })
hi("RainbowDelimiterGreen",   { fg = p.green })
hi("RainbowDelimiterViolet",  { fg = p.purple })
hi("RainbowDelimiterCyan",    { fg = p.indigo })
hi("TSRainbowRed",            { fg = p.red })
hi("TSRainbowYellow",         { fg = p.yellow })
hi("TSRainbowBlue",           { fg = p.blue })
hi("TSRainbowOrange",         { fg = p.green })
hi("TSRainbowGreen",          { fg = p.green })
hi("TSRainbowViolet",         { fg = p.purple })
hi("TSRainbowCyan",           { fg = p.indigo })

-- LSP semantic tokens --------------------------------------------------------

hi("@lsp.type.namespace",     { link = "@module" })
hi("@lsp.type.type",          { link = "@type" })
hi("@lsp.type.class",         { link = "@type" })
hi("@lsp.type.enum",          { link = "@type" })
hi("@lsp.type.interface",     { link = "@type" })
hi("@lsp.type.struct",        { link = "@type" })
hi("@lsp.type.typeParameter", { fg = p.yellow })
hi("@lsp.type.parameter",     { link = "@variable.parameter" })
hi("@lsp.type.variable",      { link = "@variable" })
hi("@lsp.type.property",      { link = "@property" })
hi("@lsp.type.enumMember",    { fg = p.yellow, bold = true })
hi("@lsp.type.function",      { link = "@function" })
hi("@lsp.type.method",        { link = "@function.method" })
hi("@lsp.type.macro",         { link = "@function.macro" })
hi("@lsp.type.decorator",     { link = "@attribute" })
hi("@lsp.type.comment",       { link = "@comment" })
hi("@lsp.type.keyword",       { link = "@keyword" })
hi("@lsp.type.string",        { link = "@string" })
hi("@lsp.type.number",        { link = "@number" })
hi("@lsp.type.operator",      { link = "@operator" })

hi("@lsp.mod.deprecated",     { strikethrough = true })
hi("@lsp.mod.readonly",       { italic = true })
hi("@lsp.mod.defaultLibrary", { italic = true })

-- Diagnostics ----------------------------------------------------------------

hi("DiagnosticError",          { fg = p.red })
hi("DiagnosticWarn",           { fg = p.yellow })
hi("DiagnosticInfo",           { fg = p.blue })
hi("DiagnosticHint",           { fg = p.grey })
hi("DiagnosticOk",             { fg = p.green })

hi("DiagnosticUnderlineError", { undercurl = true, sp = p.red })
hi("DiagnosticUnderlineWarn",  { undercurl = true, sp = p.yellow })
hi("DiagnosticUnderlineInfo",  { undercurl = true, sp = p.blue })
hi("DiagnosticUnderlineHint",  { undercurl = true, sp = p.grey })
hi("DiagnosticUnderlineOk",    { undercurl = true, sp = p.green })

hi("DiagnosticVirtualTextError", { fg = p.red,    bg = "#2a0e04" })
hi("DiagnosticVirtualTextWarn",  { fg = p.yellow, bg = "#2a2400" })
hi("DiagnosticVirtualTextInfo",  { fg = p.blue,   bg = "#002a33" })
hi("DiagnosticVirtualTextHint",  { fg = p.grey,   bg = p.bg1 })

hi("LspReferenceText",  { bg = p.bg2 })
hi("LspReferenceRead",  { bg = p.bg2 })
hi("LspReferenceWrite", { bg = p.bg2, bold = true })
hi("LspInlayHint",      { fg = p.grey, italic = true })
hi("LspSignatureActiveParameter", { fg = p.yellow, bold = true })

-- Git signs ------------------------------------------------------------------

hi("GitSignsAdd",          { fg = p.green })
hi("GitSignsChange",       { fg = p.blue })
hi("GitSignsDelete",       { fg = p.red })
hi("GitSignsAddNr",        { fg = p.green })
hi("GitSignsChangeNr",     { fg = p.blue })
hi("GitSignsDeleteNr",     { fg = p.red })

-- Indent guides (indent-blankline) -------------------------------------------

hi("IblIndent", { fg = p.bg2 })
hi("IblScope",  { fg = p.bg3 })

-- Telescope ------------------------------------------------------------------

hi("TelescopeNormal",       { fg = p.fg,   bg = p.bg1 })
hi("TelescopeBorder",       { fg = p.bg3,  bg = p.bg1 })
hi("TelescopeTitle",        { fg = p.yellow, bg = p.bg1, bold = true })
hi("TelescopeSelection",    { bg = p.bg2 })
hi("TelescopeMatching",     { fg = p.yellow, bold = true })
hi("TelescopePromptNormal", { fg = p.fg,   bg = p.bg2 })
hi("TelescopePromptBorder", { fg = p.bg3,  bg = p.bg2 })
hi("TelescopePromptTitle",  { fg = p.green, bg = p.bg2, bold = true })

-- Snacks (picker, dashboard, etc.) -------------------------------------------

hi("SnacksPickerMatch",     { fg = p.yellow, bold = true })
hi("SnacksPickerDir",       { fg = p.grey })
hi("SnacksPickerFile",      { fg = p.fg })

-- Lazy / Mason ---------------------------------------------------------------

hi("LazyH1",               { fg = p.bg1, bg = p.blue, bold = true })
hi("LazyButton",           { fg = p.fg,  bg = p.bg2 })
hi("LazyButtonActive",     { fg = p.bg1, bg = p.green })
hi("LazySpecial",          { fg = p.green })

-- Notify ---------------------------------------------------------------------

hi("NotifyERRORBorder", { fg = p.red })
hi("NotifyWARNBorder",  { fg = p.yellow })
hi("NotifyINFOBorder",  { fg = p.blue })
hi("NotifyDEBUGBorder", { fg = p.grey })
hi("NotifyTRACEBorder", { fg = p.purple })
hi("NotifyERRORIcon",   { fg = p.red })
hi("NotifyWARNIcon",    { fg = p.yellow })
hi("NotifyINFOIcon",    { fg = p.blue })
hi("NotifyDEBUGIcon",   { fg = p.grey })
hi("NotifyTRACEIcon",   { fg = p.purple })
hi("NotifyERRORTitle",  { fg = p.red })
hi("NotifyWARNTitle",   { fg = p.yellow })
hi("NotifyINFOTitle",   { fg = p.blue })
hi("NotifyDEBUGTitle",  { fg = p.grey })
hi("NotifyTRACETitle",  { fg = p.purple })

-- Noice ----------------------------------------------------------------------

hi("NoiceCmdlinePopup",       { fg = p.fg, bg = p.bg1 })
hi("NoiceCmdlinePopupBorder", { fg = p.bg3, bg = p.bg1 })
hi("NoiceCmdlineIcon",        { fg = p.yellow })

-- Mini (statusline, etc.) ----------------------------------------------------

hi("MiniStatuslineFilename",    { fg = p.fg_dim, bg = p.bg1 })
hi("MiniStatuslineModeNormal",  { fg = p.bg1, bg = p.blue, bold = true })
hi("MiniStatuslineModeInsert",  { fg = p.bg1, bg = p.green, bold = true })
hi("MiniStatuslineModeVisual",  { fg = p.bg1, bg = p.purple, bold = true })
hi("MiniStatuslineModeCommand", { fg = p.bg1, bg = p.yellow, bold = true })
hi("MiniStatuslineModeReplace", { fg = p.bg1, bg = p.red, bold = true })

-- Which-key ------------------------------------------------------------------

hi("WhichKey",          { fg = p.red })
hi("WhichKeyGroup",     { fg = p.blue })
hi("WhichKeyDesc",      { fg = p.fg })
hi("WhichKeySeparator", { fg = p.grey })
hi("WhichKeyValue",     { fg = p.grey })

-- Cmp / blink.cmp (completion) -----------------------------------------------

hi("CmpItemAbbrMatch",       { fg = p.yellow, bold = true })
hi("CmpItemAbbrMatchFuzzy",  { fg = p.yellow })
hi("CmpItemKindFunction",    { fg = p.blue })
hi("CmpItemKindMethod",      { fg = p.blue })
hi("CmpItemKindVariable",    { fg = p.fg })
hi("CmpItemKindClass",       { fg = p.yellow })
hi("CmpItemKindInterface",   { fg = p.yellow })
hi("CmpItemKindModule",      { fg = p.blue })
hi("CmpItemKindProperty",    { fg = p.fg_dim })
hi("CmpItemKindKeyword",     { fg = p.red })
hi("CmpItemKindText",        { fg = p.fg_dim })
hi("CmpItemKindSnippet",     { fg = p.indigo })
hi("CmpItemKindField",       { fg = p.fg_dim })
hi("CmpItemKindEnum",        { fg = p.yellow })
hi("CmpItemKindEnumMember",  { fg = p.purple })
hi("CmpItemKindConstant",    { fg = p.purple })
hi("CmpItemKindStruct",      { fg = p.yellow })
hi("CmpItemKindTypeParameter", { fg = p.yellow })
hi("CmpItemKindOperator",    { fg = p.fg })
hi("CmpItemKindEvent",       { fg = p.indigo })

hi("BlinkCmpMenu",           { fg = p.fg, bg = p.bg1 })
hi("BlinkCmpMenuBorder",     { fg = p.bg3, bg = p.bg1 })
hi("BlinkCmpMenuSelection",  { bg = p.bg2 })
hi("BlinkCmpLabel",          { fg = p.fg })
hi("BlinkCmpLabelMatch",     { fg = p.yellow, bold = true })
hi("BlinkCmpKind",           { fg = p.blue })
hi("BlinkCmpDoc",            { fg = p.fg, bg = p.bg1 })
hi("BlinkCmpDocBorder",      { fg = p.bg3, bg = p.bg1 })

-- Dashboard ------------------------------------------------------------------

hi("DashboardHeader",    { fg = p.blue })
hi("DashboardFooter",    { fg = p.grey })
hi("DashboardDesc",      { fg = p.green })
hi("DashboardKey",       { fg = p.red })
hi("DashboardIcon",      { fg = p.blue })
hi("DashboardShortCut",  { fg = p.indigo })

-- Lualine integration (set g:spaceduck_lualine for lualine.lua to pick up) ---

vim.g.spaceduck_lualine = {
  normal  = { a = { fg = p.bg1, bg = p.blue,   gui = "bold" }, b = { fg = p.fg, bg = p.bg2 }, c = { fg = p.grey, bg = p.bg1 } },
  insert  = { a = { fg = p.bg1, bg = p.green,  gui = "bold" } },
  visual  = { a = { fg = p.bg1, bg = p.purple, gui = "bold" } },
  replace = { a = { fg = p.bg1, bg = p.red,    gui = "bold" } },
  command = { a = { fg = p.bg1, bg = p.yellow, gui = "bold" } },
  inactive = { a = { fg = p.grey, bg = p.bg1 }, b = { fg = p.grey, bg = p.bg1 }, c = { fg = p.grey, bg = p.bg1 } },
}
