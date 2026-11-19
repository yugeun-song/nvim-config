local opt = vim.opt

opt.number = true
opt.relativenumber = false
opt.modeline = false
opt.whichwrap:append("h,l,<,>,[,]")
opt.tags = "./tags;"
opt.swapfile = false
opt.spelllang = { "en", "cjk" }
vim.o.guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor"

-- No plugin here is a remote plugin, so these provider hosts would never be used.
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

-- Neovim types a backup (a.c.orig, a.c~) by the suffix it strips, but clangd picks the language from the last
-- suffix, finds none, and answers every request with "invalid AST". A C-family backup stays plain text.
local c_family = { c = true, cpp = true, objc = true, objcpp = true, cuda = true }

local function backup_filetype(strip)
  return function(path, bufnr)
    local root = strip(path)

    if root == path or root == "" then
      return
    end

    local ft, on_detect = vim.filetype.match({ buf = bufnr, filename = vim.fn.fnameescape(root) })

    if c_family[ft] then
      return "text"
    end

    return ft, on_detect
  end
end

local backup_extension = {}

for _, ext in ipairs({
  "bak",
  "dpkg-bak",
  "dpkg-dist",
  "dpkg-old",
  "dpkg-new",
  "in",
  "new",
  "old",
  "orig",
  "pacsave",
  "pacnew",
  "rpmsave",
  "rpmnew",
}) do
  backup_extension[ext] = backup_filetype(function(path)
    return vim.fn.fnamemodify(path, ":r")
  end)
end

vim.filetype.add({
  extension = vim.tbl_extend("error", backup_extension, {
    S = "asm",
    s = "asm",
    sx = "asm",
    lds = "ld",
  }),
  pattern = {
    [".*%.lds%.S"] = "ld",
    [".*~"] = {
      backup_filetype(function(path)
        return (path:gsub("~+$", "", 1))
      end),
      { priority = 1 },
    },
  },
})
