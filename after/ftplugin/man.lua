vim.opt_local.number = vim.go.number
vim.opt_local.relativenumber = vim.go.relativenumber
vim.opt_local.signcolumn = vim.go.signcolumn
vim.opt_local.cursorline = false
vim.opt_local.scrolloff = 4

-- Parser language by section number; none for 1, 6 and 8 (commands).
local SECTION_LANG = {
  ["0"] = "c",
  ["2"] = "c",
  ["3"] = "c",
  ["4"] = "c",
  ["5"] = "c",
  ["7"] = "c",
  ["9"] = "c",
}

-- Suffixes naming another language; the rest (3p, 3ssl, 3x) are C libraries.
local SUFFIX_LANG = { am = "awk", perl = "perl", pm = "perl", tcl = "tcl" }

-- The suffix's grammar if installed, else the section's.
local function language_for(buf)
  local num, suffix = tostring(vim.b[buf].man_sect or ""):match("^(%d)%d*(%a*)$")

  if not num then
    return nil
  end

  suffix = suffix:lower()
  if suffix ~= "" then
    local lang = SUFFIX_LANG[suffix] or suffix
    local ok, loaded = pcall(vim.treesitter.language.add, lang)

    if ok and loaded then
      return lang
    elseif SUFFIX_LANG[suffix] then
      return nil
    end
  end

  return SECTION_LANG[num]
end

local buf = vim.api.nvim_get_current_buf()

pcall(function()
  local structure = require("features.ui.man_page_highlighting.structure")

  structure.highlight(buf)
  structure.close_calls(buf)
end)

local lang = language_for(buf)

if lang then
  pcall(function()
    require("features.ui.man_page_highlighting.code_blocks").highlight(buf, lang)
  end)
end
