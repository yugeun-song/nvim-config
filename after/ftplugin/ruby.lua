-- The REPL keys only where irb is installed.
if vim.fn.executable("irb") == 1 then
  require("features.lang.lisp.repl").map_keys("irb", "REPL: evaluate buffer")
end
