local M = {}

M.ns = vim.api.nvim_create_namespace("dbg_panel")

-- Every panel buffer and debugger window is registered here and nowhere else;
-- modules ask this registry instead of holding their own handle, so a window the
-- user closed or a buffer Neovim wiped is never mistaken for a live one.
local buffers = {}
local windows = {}

function M.win(slot)
  local win = windows[slot]
  if win and vim.api.nvim_win_is_valid(win) then
    return win
  end
  windows[slot] = nil
  return nil
end

function M.set_win(slot, win)
  if win and vim.api.nvim_win_is_valid(win) then
    windows[slot] = win
  else
    windows[slot] = nil
  end
end

function M.forget_win(win)
  for slot, held in pairs(windows) do
    if held == win then
      windows[slot] = nil
    end
  end
end

vim.api.nvim_create_autocmd("WinClosed", {
  callback = function(ev)
    M.forget_win(tonumber(ev.match))
  end,
  desc = "Drop debugger window handles the moment their window goes away",
})

function M.buffer(key, filetype)
  local buf = buffers[key]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf, false
  end
  buf = vim.api.nvim_create_buf(false, true)
  buffers[key] = buf
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = filetype or ("dbg-" .. key)
  pcall(vim.api.nvim_buf_set_name, buf, "dbg://" .. key)
  return buf, true
end

function M.width(buf, fallback)
  local wins = vim.fn.win_findbuf(buf)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      return vim.api.nvim_win_get_width(win)
    end
  end
  return fallback or math.min(vim.o.columns, 120)
end

function M.render(buf, lines, highlights)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  for i, line in ipairs(lines) do
    lines[i] = (line:gsub("%s+$", ""))
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for _, h in ipairs(highlights or {}) do
    pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, h[1], h[2], { end_col = h[3], hl_group = h[4], priority = h[5] })
  end
end

function M.show(buf, height, name)
  local ui = require("dbg.ui")
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      ui.style_window(win, name)
      vim.api.nvim_set_current_win(win)
      return win
    end
  end
  vim.cmd("botright " .. (height or 14) .. "split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.w[win].dbg_owned = "split"
  ui.style_window(win, name)
  return win
end

-- Only one window may hold a panel.  When the same panel turns up twice, the
-- window hardest to reopen wins: managed panel, then sidebar, then loose split.
local function claim_rank(win)
  local owner = vim.w[win].dbg_owned
  if owner == nil then
    return 3
  end
  if owner == "sidebar" then
    return 2
  end
  return 1
end

local enforcing = false

function M.enforce_unique(buf)
  if enforcing or not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local wins = {}
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      wins[#wins + 1] = win
    end
  end
  if #wins < 2 then
    return
  end
  table.sort(wins, function(a, b)
    return claim_rank(a) > claim_rank(b)
  end)
  enforcing = true
  local ok, err = pcall(function()
    for i = 2, #wins do
      local win = wins[i]
      if vim.w[win].dbg_owned == "sidebar" then
        require("dbg.layout").sidebar_next_free()
      elseif #vim.api.nvim_list_wins() > 1 then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)
  enforcing = false
  if not ok then
    error(err)
  end
end

function M.stopped_session()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return nil, "nvim-dap is not available."
  end
  local session = dap.session()
  if not session then
    return nil, "No debug session is running."
  end
  if not session.current_frame then
    return nil, "The session is not stopped."
  end
  return session
end

return M
