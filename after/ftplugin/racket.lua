vim.keymap.set("i", "'", "'", { buffer = true })
vim.keymap.set("i", "`", "`", { buffer = true })

local repl = require("lisp_repl")
local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { buffer = true, desc = desc })
end
map("n", "<localleader>r", repl.toggle, "REPL: toggle racket")
map("n", "<localleader>e", repl.eval_toplevel, "REPL: evaluate top-level form")
map("x", "<localleader>e", repl.eval_selection, "REPL: evaluate selection")
map("n", "<localleader>b", repl.eval_buffer, "REPL: save, run the module and enter it")
map("n", "<localleader>i", repl.interrupt, "REPL: interrupt")
map("n", "<localleader>q", repl.stop, "REPL: quit racket")
