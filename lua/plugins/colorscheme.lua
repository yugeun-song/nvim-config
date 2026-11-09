-- Parts adapted from https://github.com/rebelot/kanagawa.nvim (MIT). See THIRD-PARTY-NOTICES.
local default = "spaceduck-remix"

-- Two lines: the confirmed colorscheme and the default it replaced; a new default drops the choice.
local function record()
  return require("features.util.storage").path("state", "colorscheme_choice")
end

return {
  { "sainnhe/gruvbox-material" },
  {
    "rebelot/kanagawa.nvim",
    lazy = true,
    opts = {
      colors = { theme = { all = { ui = { bg_gutter = "none" } } } },
      overrides = function(colors)
        local ui = colors.theme.ui
        local dark = { bg = ui.bg_m3, fg = ui.fg_dim }

        return {
          NormalFloat = { bg = "none" },
          FloatBorder = { bg = "none" },
          FloatTitle = { bg = "none" },
          LazyNormal = dark,
          MasonNormal = dark,
          NoicePopup = dark,
          NoicePopupBorder = { bg = ui.bg_m3, fg = ui.float.fg_border },
          BlinkCmpDoc = dark,
          BlinkCmpDocSeparator = dark,
        }
      end,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        local ok, lines = pcall(vim.fn.readfile, record())

        -- The default was "spaceduck" before its rename.
        if ok and lines[2] == "spaceduck" then
          lines[2] = "spaceduck-remix"
          pcall(vim.fn.writefile, lines, record())
        end

        local chosen = ok and lines[2] == default and (lines[1] or ""):match("%S+")

        if ok and not chosen then
          os.remove(record())
        end

        if not (chosen and pcall(vim.cmd.colorscheme, chosen)) then
          vim.cmd.colorscheme(default)
        end
      end,
    },
  },
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          colorschemes = {
            confirm = function(picker, item)
              require("snacks.picker.config.sources").colorschemes.confirm(picker, item)
              if not item then
                return
              end

              if item.text == default then
                os.remove(record())
              else
                pcall(vim.fn.writefile, { item.text, default }, record())
              end
            end,
          },
        },
      },
    },
  },
}
