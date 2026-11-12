local M = {}

-- Over SSH these tools would act on the remote host's IME.
function M.remote()
  return (vim.env.SSH_CONNECTION or "") ~= "" or (vim.env.SSH_TTY or "") ~= ""
end

-- Installed switch commands, preferred first. opts.build = false: never start the Windows helper's build.
function M.english_commands(opts)
  if M.remote() then
    return {}
  end

  local candidates

  if vim.fn.has("mac") == 1 then
    candidates = {
      { "macism", "com.apple.keylayout.ABC" },
      { "im-select", "com.apple.keylayout.ABC" },
      { "issw", "com.apple.keylayout.ABC" },
    }
  elseif vim.fn.has("win32") == 1 then
    -- windows_ime_helper turns the IME to its English mode and keeps the keyboard layout; im-select.exe switches
    -- layouts.
    local ime_helper = require("features.util.windows.ime_helper").path(opts)

    candidates = { { "im-select.exe", "1033" } }
    if ime_helper then
      table.insert(candidates, 1, { ime_helper, "ime-english" })
    end
  elseif vim.fn.has("wsl") == 1 then
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

  return vim.tbl_filter(function(cmd)
    return vim.fn.executable(cmd[1]) == 1
  end, candidates)
end

-- Queries that fail unless the input method runs (fcitx5-remote exits 1 without fcitx5).
local PROBES = {
  ["fcitx5-remote"] = { "fcitx5-remote", "-n" },
  ["fcitx-remote"] = { "fcitx-remote" },
  ibus = { "ibus", "engine" },
}

-- Whether cmd's input method answers; nil when it cannot be asked.
function M.answers(cmd)
  local probe = PROBES[cmd[1]]

  if not probe then
    return nil
  end

  local ok, res = pcall(function()
    return vim.system(probe, { text = true }):wait(2000)
  end)

  return ok and res.code == 0 and vim.trim(res.stdout or "") ~= ""
end

-- Prints Caps Lock as 1 or 0 every 200 ms; the first write after Neovim closes the pipe ends it.
local CAPS_JXA = 'ObjC.import("AppKit"); const out = $.NSFileHandle.fileHandleWithStandardOutput; for (;;) { '
  .. 'out.writeData($(($.NSEvent.modifierFlags & 65536) ? "1\\n" : "0\\n").dataUsingEncoding(4)); delay(0.2); }'

local function korean_source(out)
  return out:find("Korean", 1, true) ~= nil or out:find("Gureum.han", 1, true) ~= nil
end

function M.caps_led()
  return vim.fn.glob("/sys/class/leds/input*::capslock/brightness", true, true)[1]
end

-- What the statusline reads: im = { cmd, hangul(stdout) }; Caps Lock as a sysfs LED node (caps) or as a
-- command printing 1 or 0 per line (caps_watch); or both from one watcher printing <caps><ime> (watch).
function M.indicators()
  if M.remote() then
    return {}
  end

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

  -- Windows: one windows_ime_helper prints Caps Lock and the IME's mode as two digits, at start and on every change.
  -- While it is still being built, the indicators are there and start when it lands.
  if vim.fn.has("win32") == 1 then
    local ime_helper = require("features.util.windows.ime_helper")

    return (ime_helper.path() or ime_helper.is_building()) and { watch = true } or {}
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

  return { im = im, caps = M.caps_led() }
end

return M
