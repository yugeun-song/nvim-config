-- A Lisp quote is a prefix: ' and ` type one character, not an autopair.
vim.keymap.set("i", "'", "'", { buffer = true })
vim.keymap.set("i", "`", "`", { buffer = true })
-- alive-lsp indents macros it has not loaded as plain calls; format only on request.
vim.b.autoformat = false

if not vim.api.nvim_buf_get_name(0):match("%.el$") then
  require("lisp_repl").map_keys("sbcl", "REPL: evaluate buffer")
end
