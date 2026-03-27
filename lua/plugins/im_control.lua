local function get_im_command()
  if vim.fn.executable("fcitx5-remote") == 1 then
    return "fcitx5-remote -c"
  elseif vim.fn.executable("im-select.exe") == 1 then
    return "im-select.exe 1033"
  elseif vim.fn.executable("issw") == 1 then
    return "issw com.apple.keylayout.ABC"
  end
  return nil
end

local im_command = get_im_command()

if im_command then
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = vim.api.nvim_create_augroup("IMControl", { clear = true }),
    pattern = "*",
    callback = function()
      vim.fn.system(im_command)
    end,
  })
end
