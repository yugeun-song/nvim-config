vim.keymap.set("i", "'", "'", { buffer = true })
vim.keymap.set("i", "`", "`", { buffer = true })
-- alive-lsp indents macros it has not loaded as plain calls; format only on request.
vim.b.autoformat = false
