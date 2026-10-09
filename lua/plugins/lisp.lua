local alive_root = vim.fn.stdpath("data") .. "/alive-lsp"

local function ocicl_lint_parser(output, bufnr, cwd)
  return require("lint.parser").from_pattern(
    "^(.+):(%d+):(%d+): ([%w%-]+): (.+)$",
    { "file", "lnum", "col", "code", "message" },
    nil,
    { source = "ocicl lint", severity = vim.diagnostic.severity.INFO }
  )(output, bufnr, cwd)
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "commonlisp" } },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        alive_lsp = {
          enabled = vim.fn.executable("sbcl") == 1 and vim.uv.fs_stat(alive_root .. "/ocicl.csv") ~= nil,
          mason = false,
          cmd = { "sbcl", "--script", vim.fn.stdpath("config") .. "/scripts/alive-lsp-stdio.lisp", alive_root },
          filetypes = { "lisp" },
          root_dir = function(bufnr, on_dir)
            if vim.api.nvim_buf_get_name(bufnr):match("%.el$") then
              return
            end
            on_dir(vim.fs.root(bufnr, function(name)
              return name == "ocicl.csv" or name == ".git" or name:match("%.asd$") ~= nil
            end))
          end,
          settings = { alive = { format = { indentWidth = 2 } } },
        },
      },
    },
  },
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = { lisp = { "ocicl_lint" } },
      linters = {
        ocicl_lint = {
          cmd = "ocicl",
          args = { "-c", "never", "lint" },
          stdin = false,
          append_fname = true,
          ignore_exitcode = true,
          parser = ocicl_lint_parser,
          condition = function(ctx)
            return not vim.bo.modified and not ctx.filename:match("%.el$")
          end,
        },
      },
    },
  },
}
