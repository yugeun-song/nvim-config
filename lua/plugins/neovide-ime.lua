return {
  "sevenc-nanashi/neov-ime.nvim",
  cond = function()
    return vim.g.neovide ~= nil
  end,
  lazy = false,
  init = function()
    vim.g.neovime_manual_setup = true
  end,
  config = function()
    local neovide = _G.neovide
    if not neovide then
      return
    end
    local ime = require("neov-ime")
    local composing = false
    -- fcitx5 answers every IME cursor-area update with an empty preedit, and neov-ime
    -- re-sets the cursor on each one, dropping curswant ($ then j). Pass only the one ending a preedit.
    neovide.preedit_handler = function(text, ...)
      local active = text ~= nil and text ~= ""
      if active or composing then
        composing = active
        ime.preedit_handler(text, ...)
      end
    end
    neovide.commit_handler = ime.commit_handler
  end,
}
