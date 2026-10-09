vim.keymap.set("i", "'", "'", { buffer = true })
vim.keymap.set("i", "`", "`", { buffer = true })
-- alive-lsp indents macros it has not loaded as plain calls; format only on request.
vim.b.autoformat = false

if not vim.api.nvim_buf_get_name(0):match("%.el$") then
  local repl = require("lisp_repl")
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = true, desc = desc })
  end
  map("n", "<localleader>r", repl.toggle, "REPL: toggle sbcl")
  map("n", "<localleader>e", repl.eval_toplevel, "REPL: evaluate top-level form")
  map("x", "<localleader>e", repl.eval_selection, "REPL: evaluate selection")
  map("n", "<localleader>b", repl.eval_buffer, "REPL: evaluate buffer")
  map("n", "<localleader>i", repl.interrupt, "REPL: interrupt")
  map("n", "<localleader>q", repl.stop, "REPL: quit sbcl")
end
