-- :checkhealth features.input_method
local status = require("features.feature_status")

local M = {}

function M.check()
  vim.health.start("Input method and keyboard")
  status.available("Korean langmap (Normal-mode keys typed in 한글 work)")

  local backends = require("features.input_method.per_os_backends")
  local cmd = backends.english_command({ build = false })

  if cmd then
    status.available("English on leaving Insert", table.concat(cmd, " "))
  else
    local advice = status.MACOS and "macism, im-select or issw"
      or status.WINDOWS and "Visual Studio's cl or clang targeting MSVC (builds native/windows_ime_helper.c), or im-select.exe"
      or "fcitx5, fcitx or ibus"

    status.blocked("English on leaving Insert", "no IME tool found", { "install " .. advice })
  end

  if status.WINDOWS then
    local ime_helper = require("features.windows_platform.windows_ime_helper")
    local path, why = ime_helper.path({ build = false })

    if path then
      status.available("IME and Caps Lock in the statusline", path .. " watch")
    else
      status.blocked("IME and Caps Lock in the statusline", "windows_ime_helper " .. why, {
        "Visual Studio's cl, or clang targeting MSVC, on PATH builds native/windows_ime_helper.c in the background at startup",
      })
    end

    if ime_helper.watch_failure() then
      status.blocked("IME and Caps Lock in the statusline", "the watcher stopped: " .. ime_helper.watch_failure())
    end

    -- Everything windows_ime_helper reported this session, shims included (each was shown once as a notification).
    for _, line in ipairs(ime_helper.reports()) do
      vim.health.info("windows_ime_helper reported " .. line)
    end
  elseif status.LINUX or status.MACOS then
    local sources = backends.indicators()

    if sources.im then
      status.available("IME in the statusline", table.concat(sources.im.cmd, " "))
    else
      status.blocked(
        "IME in the statusline",
        "missing " .. (status.LINUX and "fcitx5-remote" or "macism, im-select or issw")
      )
    end

    if sources.caps or sources.caps_watch then
      status.available("Caps Lock in the statusline", sources.caps or sources.caps_watch[1])
    else
      status.blocked(
        "Caps Lock in the statusline",
        status.LINUX and "no /sys/class/leds/input*::capslock node" or "no osascript"
      )
    end
  else
    status.unsupported("IME and Caps Lock in the statusline", "they read fcitx5 and a sysfs LED, or macOS tools")
  end

  if vim.g.neovide then
    if status.plugin_installed("neov-ime.nvim") then
      status.available("IME preedit in Neovide (neov-ime)")
    else
      status.blocked("IME preedit in Neovide (neov-ime)", "the plugin is not installed", { ":Lazy install" })
    end
  end
end

return M
