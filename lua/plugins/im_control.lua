local function english_command()
  local candidates
  if vim.fn.has("mac") == 1 then
    candidates = {
      { "macism", "com.apple.keylayout.ABC" },
      { "im-select", "com.apple.keylayout.ABC" },
      { "issw", "com.apple.keylayout.ABC" },
    }
  elseif vim.fn.has("win32") == 1 or vim.fn.has("wsl") == 1 then
    candidates = { { "im-select.exe", "1033" } }
  else
    local fcitx = { { "fcitx5-remote", "-c" }, { "fcitx-remote", "-c" } }
    local ibus = { { "ibus", "engine", vim.g.ibus_english_engine or "xkb:us::eng" } }
    if (vim.env.XMODIFIERS or ""):find("ibus") then
      candidates = vim.list_extend(ibus, fcitx)
    else
      candidates = vim.list_extend(fcitx, ibus)
    end
  end
  for _, cmd in ipairs(candidates) do
    if vim.fn.executable(cmd[1]) == 1 then
      return cmd
    end
  end
  return nil
end

return {
  "im_control",
  virtual = true,
  config = function()
    vim.opt.langmap =
      "ㅁa,ㅠb,ㅊc,ㅇd,ㄷe,ㄹf,ㅎg,ㅗh,ㅑi,ㅓj,ㅏk,ㅣl,ㅡm,ㅜn,ㅐo,ㅔp,ㅂq,ㄱr,ㄴs,ㅅt,ㅕu,ㅍv,ㅈw,ㅌx,ㅛy,ㅋz,ㅃQ,ㅉW,ㄸE,ㄲR,ㅆT,ㅒO,ㅖP"

    local cmd = english_command()
    if cmd then
      vim.api.nvim_create_autocmd({ "InsertLeave", "FocusGained" }, {
        group = vim.api.nvim_create_augroup("IMControl", { clear = true }),
        callback = function()
          pcall(vim.system, cmd, { stdout = false, stderr = false })
        end,
      })
    end

    if vim.g.neovide or not (vim.env.TERM or ""):find("^foot") or vim.uv.guess_handle(2) ~= "tty" then
      return
    end
    -- foot's private IME mode: CSI ? 737769 h enables the input method, l disables it.
    local foot_ime = vim.api.nvim_create_augroup("FootIME", { clear = true })
    local function foot_send(seq)
      pcall(vim.fn.chansend, vim.v.stderr, seq)
    end
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = foot_ime,
      callback = function()
        foot_send("\27[?737769h")
      end,
    })
    vim.api.nvim_create_autocmd({ "InsertLeave", "VimEnter" }, {
      group = foot_ime,
      callback = function()
        foot_send("\27[?737769l")
      end,
    })
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = foot_ime,
      callback = function()
        foot_send("\27[?737769h")
      end,
    })
  end,
}
