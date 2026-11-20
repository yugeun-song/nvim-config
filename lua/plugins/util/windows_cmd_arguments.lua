-- Windows: no linter, and no formatter that starts through cmd.exe, for a file whose path cmd.exe would read as commands
-- (lua/features/util/windows/cmd_arguments.lua). lua/config/lazy.lua imports this directory after the languages, so
-- every linter and formatter they add is checked.
if vim.fn.has("win32") == 0 then
  return {}
end

return {
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function()
      require("features.util.windows.cmd_arguments").guard_lint()
    end,
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters = opts.formatters or {}
      require("features.util.windows.cmd_arguments").guard_formatters(opts.formatters_by_ft, opts.formatters)
    end,
  },
}
