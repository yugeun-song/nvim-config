-- Following changes made outside Neovim (lua/features/editing/reload_on_external_change.lua).
return {
  "reload_on_external_change",
  virtual = true,
  -- An external change matters from the first screen on; checking before it gains nothing.
  event = "VeryLazy",
  config = function()
    require("features.editing.reload_on_external_change").setup()
  end,
}
