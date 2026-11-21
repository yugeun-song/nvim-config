-- No session written or read with a file name that would run as a command (lua/features/editor/session_guard.lua).
return {
  "folke/persistence.nvim",
  optional = true,
  opts = function()
    require("features.editor.session_guard").install()
  end,
}
