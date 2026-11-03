local M = {}

function M.english_command()
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

-- What the statusline reads: the Caps Lock LED node and whether fcitx5 reports the input method.
function M.indicators()
  return {
    caps = vim.fn.glob("/sys/class/leds/input*::capslock/brightness", true, true)[1],
    im = vim.fn.executable("fcitx5-remote") == 1,
  }
end

return M
