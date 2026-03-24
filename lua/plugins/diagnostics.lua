vim.diagnostic.config({
  virtual_text = false,
  signs = true,
  underline = true,
})

vim.lsp.inlay_hint.enable(false)

vim.api.nvim_create_autocmd("CursorHold", {
  callback = function()
    vim.diagnostic.open_float(nil, {
      focusable = false,
      border = "rounded",
      source = "always",
    })
  end,
})

vim.opt.updatetime = 500
