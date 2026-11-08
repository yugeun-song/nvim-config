-- A Racket quote is a prefix: ' and ` type one character, not an autopair.
vim.keymap.set("i", "'", "'", { buffer = true })
vim.keymap.set("i", "`", "`", { buffer = true })

require("features.languages.lisp.repl").map_keys("racket", "REPL: save, run the module and enter it")
