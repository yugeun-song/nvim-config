vim.opt_local.number = vim.go.number
vim.opt_local.relativenumber = vim.go.relativenumber
vim.opt_local.signcolumn = vim.go.signcolumn
vim.opt_local.cursorline = false
vim.opt_local.scrolloff = 4

-- Parser language by section. A suffix such as 3p or 3type is still C; any
-- other suffix names its own language.
local SECTION_LANG = {
  ["0"] = "c",
  ["2"] = "c",
  ["3"] = "c",
  ["4"] = "c",
  ["5"] = "c",
  ["7"] = "c",
  ["9"] = "c",
}

local function language_for(buf)
  local sect = tostring(vim.b[buf].man_sect or "")
  local suffix = sect:match("^%d+(%a+)$")
  if suffix then
    local lang = suffix:lower()
    if lang == "p" or lang == "type" or lang == "const" or lang == "head" or lang == "attr" then
      return "c"
    end
    return lang
  end
  return SECTION_LANG[sect:sub(1, 1)]
end

local buf = vim.api.nvim_get_current_buf()

pcall(function()
  local structure = require("man_code.structure")
  structure.highlight(buf)
  structure.close_calls(buf)
end)

local lang = language_for(buf)
if lang then
  pcall(function()
    require("man_code").highlight(buf, lang)
  end)
end
