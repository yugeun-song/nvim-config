local M = {}

local changed = false

local function nested(ttys)
  if vim.env.TMUX or vim.env.STY or vim.env.NVIM then
    return true
  end
  for _, ui in ipairs(ttys) do
    local term = ui.term_name or ""
    if term:find("^tmux") or term:find("^screen") then
      return true
    end
  end
  return false
end

local function restore()
  if changed then
    vim.api.nvim_ui_send("\027]111\007")
    changed = false
  end
end

local function follow()
  local ttys = vim.tbl_filter(function(ui)
    return ui.stdout_tty
  end, vim.api.nvim_list_uis())
  if #ttys == 0 then
    return
  end
  local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  if not bg or not vim.o.termguicolors or nested(ttys) then
    restore()
    return
  end
  vim.api.nvim_ui_send(("\027]11;#%06x\007"):format(bg))
  changed = true
end

function M.setup()
  local group = vim.api.nvim_create_augroup("terminal_background", { clear = true })
  vim.api.nvim_create_autocmd({ "UIEnter", "ColorScheme", "VimResume" }, {
    group = group,
    callback = follow,
    desc = "Give the terminal Normal's background, so its padding matches the editor",
  })
  vim.api.nvim_create_autocmd({ "VimSuspend", "VimLeavePre" }, {
    group = group,
    callback = restore,
    desc = "Give the terminal its own background back",
  })
end

return M
