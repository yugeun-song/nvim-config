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
