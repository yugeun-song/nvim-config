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

-- Prints Caps Lock as 1 or 0 every 200 ms; the first write after Neovim closes the pipe ends it.
local CAPS_JXA = 'ObjC.import("AppKit"); const out = $.NSFileHandle.fileHandleWithStandardOutput; for (;;) { '
  .. 'out.writeData($(($.NSEvent.modifierFlags & 65536) ? "1\\n" : "0\\n").dataUsingEncoding(4)); delay(0.2); }'

local function korean_source(out)
  return out:find("Korean", 1, true) ~= nil or out:find("Gureum.han", 1, true) ~= nil
end

-- What the statusline reads: im = { cmd, hangul(stdout) }; Caps Lock as a sysfs LED node (caps) or as a
-- command printing 1 or 0 per line (caps_watch).
function M.indicators()
  if vim.fn.has("mac") == 1 then
    local im = nil

    for _, name in ipairs({ "macism", "im-select", "issw" }) do
      if vim.fn.executable(name) == 1 then
        im = { cmd = { name }, hangul = korean_source }

        break
      end
    end

    local watch = vim.fn.executable("osascript") == 1 and { "osascript", "-l", "JavaScript", "-e", CAPS_JXA } or nil

    return { im = im, caps_watch = watch }
  end

  if vim.fn.has("linux") == 0 then
    return {}
  end

  local im = nil

  if vim.fn.executable("fcitx5-remote") == 1 then
    im = {
      cmd = { "fcitx5-remote", "-n" },
      hangul = function(out)
        return vim.trim(out) == "hangul"
      end,
    }
  end

  return { im = im, caps = vim.fn.glob("/sys/class/leds/input*::capslock/brightness", true, true)[1] }
end

return M
