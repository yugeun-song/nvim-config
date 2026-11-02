local function clang_format_fallback(buf)
  local bo = vim.bo[buf]
  local width = bo.shiftwidth > 0 and bo.shiftwidth or bo.tabstop
  return ("{BasedOnStyle: LLVM, IndentWidth: %d, TabWidth: %d, UseTab: %s, BreakBeforeBraces: Custom, BraceWrapping: {AfterFunction: true}, AllowShortFunctionsOnASingleLine: None, SortIncludes: Never}"):format(
    width,
    bo.tabstop,
    bo.expandtab and "Never" or "ForIndentation"
  )
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = { servers = { oxfmt = { enabled = false } } },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        javascript = { "oxfmt" },
        javascriptreact = { "oxfmt" },
        typescript = { "oxfmt" },
        typescriptreact = { "oxfmt" },
        json = { "oxfmt" },
        jsonc = { "oxfmt" },
        json5 = { "oxfmt" },
        css = { "oxfmt" },
        scss = { "oxfmt" },
        less = { "oxfmt" },
        html = { "oxfmt" },
        toml = { "taplo" },
        c = { "clang_format" },
        cpp = { "clang_format" },
      },
      formatters = {
        clang_format = {
          prepend_args = function(_, ctx)
            local found = vim.fs.find({ ".clang-format", "_clang-format" }, {
              upward = true,
              path = ctx.dirname,
              type = "file",
            })[1]
            if found then
              return {}
            end
            return { "--style=" .. clang_format_fallback(ctx.buf) }
          end,
        },
      },
    },
  },
}
