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

return {
  "im_control",
  virtual = true,
  config = function()
    vim.opt.langmap =
      "ㅁa,ㅠb,ㅊc,ㅇd,ㄷe,ㄹf,ㅎg,ㅗh,ㅑi,ㅓj,ㅏk,ㅣl,ㅡm,ㅜn,ㅐo,ㅔp,ㅂq,ㄱr,ㄴs,ㅅt,ㅕu,ㅍv,ㅈw,ㅌx,ㅛy,ㅋz,ㅃQ,ㅉW,ㄸE,ㄲR,ㅆT,ㅒO,ㅖP"

    local im_command = get_im_command()
    if im_command then
      vim.api.nvim_create_autocmd({ "InsertLeave", "FocusGained" }, {
        group = vim.api.nvim_create_augroup("IMControl", { clear = true }),
        pattern = "*",
        callback = function()
          vim.fn.system(im_command)
        end,
      })
    end

    if not vim.g.neovide then
      local foot_ime = vim.api.nvim_create_augroup("FootIME", { clear = true })
      local function foot_send(seq)
        pcall(vim.fn.chansend, vim.v.stderr, seq)
      end
      vim.api.nvim_create_autocmd("InsertEnter", {
        group = foot_ime,
        pattern = "*",
        callback = function()
          foot_send("\27[?737769h")
        end,
      })
      vim.api.nvim_create_autocmd({ "InsertLeave", "VimEnter" }, {
        group = foot_ime,
        pattern = "*",
        callback = function()
          foot_send("\27[?737769l")
        end,
      })
      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = foot_ime,
        pattern = "*",
        callback = function()
          foot_send("\27[?737769h")
        end,
      })
    end
  end,
}
