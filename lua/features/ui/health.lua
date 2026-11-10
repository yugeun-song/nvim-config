-- :checkhealth features.ui
local status = require("features.util.feature_status")

local M = {}

function M.check()
  vim.health.start("Appearance")
  status.available("Colorscheme", vim.g.colors_name or "Neovim's default")
  status.available("Dashboard header, terminal background, keystroke display (<leader>uK)")

  if status.find("git") then
    status.available("Git tag in the statusline", "git")
  else
    status.blocked("Git tag in the statusline", "git is not on PATH")
  end

  local missing = {}

  for _, lang in ipairs({ "markdown", "markdown_inline" }) do
    if not status.parser(lang) then
      missing[#missing + 1] = lang
    end
  end

  if #missing == 0 then
    status.available("Markdown rendering (markview)")
  else
    status.blocked("Markdown rendering (markview)", "no tree-sitter parser for " .. table.concat(missing, ", "), {
      ":TSInstall " .. table.concat(missing, " "),
    })
  end

  if vim.g.neovide then
    status.available("Neovide settings and IME", "running in Neovide")
  elseif status.find("neovide") then
    status.available("Neovide settings and IME", "neovide installed")
  else
    status.blocked("Neovide settings and IME", "neovide is not installed", { "https://neovide.dev/" })
  end

  if status.WINDOWS then
    status.unsupported("Man page highlighting", "no man command")
  else
    status.programs("Man page highlighting", { "man" })
  end
end

return M
