-- :checkhealth features.windows_platform
local status = require("features.feature_status")

local M = {}

function M.check()
  vim.health.start("Windows platform")

  if not status.WINDOWS then
    status.unsupported("executable() memory and winctl", "they make up for what Windows lacks")

    return
  end

  if vim.fn.exepath == require("features.windows_platform.executable_lookup_cache").exepath then
    status.available(
      "executable() and exepath() with a memory",
      "per PATH, in stdpath('cache')/nvim-config/executable_lookup_cache.json"
    )
  else
    status.blocked("executable() and exepath() with a memory", "not installed by init.lua")
  end

  local path, why = require("features.windows_platform.winctl").path({ build = false })

  if path then
    status.available("winctl (IME, indicators, window raise, shims)", path)
  else
    status.blocked("winctl (IME, indicators, window raise, shims)", why, {
      "Visual Studio's cl, or clang targeting MSVC, on PATH builds scripts/winctl.c in the background at startup",
    })
  end
end

return M
