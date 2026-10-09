local opt = vim.opt
opt.number = true
opt.relativenumber = false
opt.modeline = false
opt.whichwrap:append("h,l,<,>,[,]")
opt.tags = "./tags;,tags;"
opt.swapfile = false
opt.spelllang = { "en", "cjk" }
vim.o.guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor"

-- No plugin here is a remote plugin, so these provider hosts would never be used.
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

vim.filetype.add({
  extension = {
    S = "asm",
    s = "asm",
    sx = "asm",
    lds = "ld",
  },
  pattern = {
    [".*%.lds%.S"] = "ld",
  },
})
