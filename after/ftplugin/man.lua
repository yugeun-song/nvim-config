vim.opt_local.signcolumn = "no"
vim.opt_local.cursorline = false
vim.opt_local.scrolloff = 4

-- The code inside a man page gets the same parser the editor uses on a source
-- file of that language. Which language the page is written about comes from
-- its section: 2 and 9 are kernel and syscall interfaces, 3 is the C library
-- unless the page names another language in its extension.
local SECTION_LANG = {
  ["0"] = "c", ["2"] = "c", ["3"] = "c", ["4"] = "c", ["5"] = "c", ["7"] = "c", ["9"] = "c",
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
  pcall(function() require("man_code").highlight(buf, lang) end)
end
