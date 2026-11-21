-- The text past a buffer's 'textwidth', tinted in every window that shows the buffer; lines within it show nothing, where
-- 'colorcolumn' draws a band down every line. A buffer takes part through M.enable(). A later 'textwidth' (an
-- .editorconfig's max_line_length) moves the edge, and 0 removes it. The tint is TextOverflow, ColorColumn's colors
-- unless a colorscheme sets it, under the search highlight.
local M = {}

local GROUP = "TextOverflow"
-- Below 'hlsearch' (0): a match found past the edge still shows as one.
local PRIORITY = -1

local enabled = {}
local installed = false

local function set_highlight()
  vim.api.nvim_set_hl(0, GROUP, { link = "ColorColumn", default = true })
end

-- The window's match follows the buffer it shows: added, moved to a new width, or removed.
local function sync(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local width = enabled[buf] and vim.bo[buf].textwidth or 0
  local have = vim.w[win].text_overflow

  if have and have.width == width then
    return
  end

  if have then
    pcall(vim.fn.matchdelete, have.id, win)
    vim.w[win].text_overflow = nil
  end

  if width > 0 then
    -- From the first character that ends past the edge: a wide one across it too, which starts within it.
    local id = vim.fn.matchadd(GROUP, (".\\%%>%dv.*"):format(width + 1), PRIORITY, -1, { window = win })

    vim.w[win].text_overflow = { id = id, width = width }
  end
end

local function sync_buffer(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    sync(win)
  end
end

local function install()
  if installed then
    return
  end

  installed = true
  set_highlight()

  local group = vim.api.nvim_create_augroup("text_overflow", { clear = true })

  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlight })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinNew", "WinEnter" }, {
    group = group,
    callback = function()
      sync(vim.api.nvim_get_current_win())
    end,
  })

  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = "textwidth",
    callback = function()
      sync_buffer(vim.api.nvim_get_current_buf())
    end,
  })

  -- OptionSet does not fire during startup, where a file given to Neovim is opened.
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        sync(win)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      enabled[args.buf] = nil
    end,
  })
end

function M.enable(buf)
  install()
  enabled[buf] = true
  sync_buffer(buf)
end

return M
