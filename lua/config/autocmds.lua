vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp" },
  callback = function()
    vim.opt_local.tabstop = 8
    vim.opt_local.shiftwidth = 8
    vim.opt_local.expandtab = false
    vim.opt_local.softtabstop = 0
    vim.opt_local.list = true
    -- Optional : vim.opt_local.listchars:append("trail:X")
    vim.b.autoformat = false
  end,
  desc = "Apply Linux Kernel Style and disable autoformatting for C/H files",
})
