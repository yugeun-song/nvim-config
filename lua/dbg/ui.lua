local M = {}

M.groups = {
  DbgPanelTitle = { link = "Title" },
  DbgPanelRule = { link = "WinSeparator" },
  DbgAddr = { link = "Constant" },
  DbgValue = { link = "Normal" },
  DbgChanged = { link = "DiagnosticWarn" },
  DbgSymbol = { link = "Function" },
  DbgAscii = { link = "String" },
  DbgKey = { link = "Identifier" },
  DbgWarn = { link = "DiagnosticWarn" },
  DbgError = { link = "DiagnosticError" },
  DbgMuted = { link = "Comment" },
  DbgStack = { link = "DiagnosticWarn" },
  DbgCode = { link = "DiagnosticError" },
  DbgData = { link = "Special" },
  -- The program counter line, in source and in disassembly.  CursorLine is not
  -- enough: it marks where the cursor is, not where the program stopped.
  DbgStopLine = { link = "Visual", force = true },
  DbgStopSign = { link = "DiagnosticOk", force = true },
  DbgInlineValue = { link = "NvimDapViewVirtualText", force = false },
}

-- Background only, borrowed from a theme group so it stays theme-aware; with no
-- foreground set, every syntax colour on the line survives.
local function pc_background()
  for _, source in ipairs({ "DiffAdd", "Visual", "CursorLine" }) do
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = source, link = false })
    if ok and hl and hl.bg then
      return hl.bg
    end
  end
  return nil
end

function M.setup_highlights()
  for name, spec in pairs(M.groups) do
    if vim.fn.hlexists(name) == 0 or spec.force then
      vim.api.nvim_set_hl(0, name, spec)
    end
  end
  local bg = pc_background()
  vim.api.nvim_set_hl(0, "DbgPcLine", bg and { bg = bg } or { link = "Visual" })
  vim.api.nvim_set_hl(0, "DbgBranchTaken", { link = "DiagnosticOk" })
  vim.api.nvim_set_hl(0, "DbgBranchUnknown", { link = "Comment" })
  -- A branch that will not be taken is dimmed, not left out: leaving it out
  -- reads as "there is no branch here", which is a different fact.
  vim.api.nvim_set_hl(0, "DbgBranchNotTaken", { link = "NonText" })
end

-- Undo style_window, so a window that used to hold a panel can go back to being
-- an ordinary editor window.
function M.unstyle_window(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  for opt, value in pairs({
    winbar = "",
    winhighlight = "",
    signcolumn = "auto",
    wrap = true,
    winfixheight = false,
    winfixbuf = false,
    number = vim.o.number,
    relativenumber = vim.o.relativenumber,
    list = vim.o.list,
  }) do
    pcall(function()
      vim.wo[win][opt] = value
    end)
  end
end

function M.banner(title, width, right)
  width = math.max(24, width or 80)
  local label = ("[ %s ]"):format(title)
  local tail = right and (" " .. right .. " ") or ""
  local room = width - vim.fn.strdisplaywidth(label) - vim.fn.strdisplaywidth(tail) - 2
  local left = math.max(2, math.floor(room / 2))
  local rest = math.max(2, room - left)
  return ("%s%s%s%s"):format(string.rep("─", left), label, string.rep("─", rest), tail)
end

function M.banner_hl(lnum, line, title)
  local s, e = line:find("%[ " .. vim.pesc(title) .. " %]")
  local hls = { { lnum, 0, #line, "DbgPanelRule" } }
  if s then
    hls[#hls + 1] = { lnum, s - 1, e, "DbgPanelTitle" }
  end
  return hls
end

function M.style_window(win, name)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  vim.wo[win].list = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].winfixheight = true
  vim.wo[win].winhighlight = "Normal:NormalFloat,CursorLine:Visual,WinSeparator:WinSeparator"
  if name then
    vim.wo[win].winbar = "%#DbgPanelTitle# " .. name .. " %*"
  end
end

function M.is_pointerish(hi, lo)
  if hi == 0 and lo < 0x10000 then
    return false
  end
  return true
end

return M
