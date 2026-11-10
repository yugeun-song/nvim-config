-- Korean input: the langmap, English on leaving Insert, the 한/EN and Caps Lock indicators in the statusline, and the
-- IME preedit in Neovide (lua/features/editor/korean_input/).
return {
  {
    "korean_input",
    virtual = true,
    -- At startup: keys typed while Neovim starts run before VeryLazy, and the langmap must map them too.
    lazy = false,
    config = function()
      require("features.editor.korean_input").setup()
    end,
  },
  {
    -- The statusline marks: lualine itself comes with VeryLazy, and their readers start processes.
    "korean_input_indicators",
    virtual = true,
    event = "VeryLazy",
    config = function()
      require("features.editor.korean_input.indicator").start()
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      for i, component in ipairs(require("features.editor.korean_input.indicator").statusline_components()) do
        table.insert(opts.sections.lualine_x, i, component)
      end
    end,
  },
  {
    "sevenc-nanashi/neov-ime.nvim",
    cond = function()
      return vim.g.neovide ~= nil
    end,
    lazy = false,
    init = function()
      vim.g.neovime_manual_setup = true
    end,
    config = function()
      ---@diagnostic disable-next-line: undefined-field
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
  },
}
