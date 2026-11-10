-- Following changes made outside Neovim (lua/features/editor/reload_on_external_change.lua).
return {
  "reload_on_external_change",
  virtual = true,
  -- With the first file: without one there is nothing to follow.
  event = "LazyFile",
  config = function()
    require("features.editor.reload_on_external_change").setup()
  end,
}
