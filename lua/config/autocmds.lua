local function augroup(name)
  return vim.api.nvim_create_augroup("lazyvim_" .. name, { clear = true })
end

vim.api.nvim_create_autocmd("FileType", {
  group = augroup("linux_kernel_style"),
  pattern = { "c", "cpp" },
  callback = function()
    local opt = vim.opt_local
    opt.tabstop = 8
    opt.shiftwidth = 8
    opt.expandtab = false
    opt.softtabstop = 0
    opt.list = true
    vim.b.autoformat = false
  end,
  desc = "Apply Linux Kernel Style and disable autoformatting for C/H files",
})

local cscope_loaded = {}
vim.api.nvim_create_autocmd("BufRead", {
  group = augroup("cscope_auto_load"),
  pattern = { "*.c", "*.h", "*.S" },
  callback = function()
    local db = vim.fn.findfile("cscope.out", ".;")
    if db == "" then
      return
    end
    local abs = vim.fn.fnamemodify(db, ":p")
    if cscope_loaded[abs] then
      return
    end
    if vim.fn.exists(":Cs") ~= 2 then
      return
    end
    cscope_loaded[abs] = true
    pcall(vim.cmd, "silent! Cs db a " .. vim.fn.fnameescape(abs) .. "::@")
  end,
  desc = "Auto-add cscope.out found upward from current buffer (once per session)",
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = augroup("kernel_tagfunc"),
  callback = function(args)
    local ft = vim.bo[args.buf].filetype
    if ft == "c" or ft == "cpp" or ft == "h" then
      vim.bo[args.buf].tagfunc = ""
    end
  end,
  desc = "Clear LSP tagfunc on C/C++/H buffers so <C-]> falls back to tags file",
})
