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

--[[
vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
  pattern = { "*.h" },
  callback = function()
    vim.cmd("setfiletype c")
  end,
  desc = "Force C filetype for .h files",
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c" },
  callback = function()
    vim.opt_local.tabstop = 8
    vim.opt_local.shiftwidth = 8
    vim.opt_local.expandtab = false
    vim.opt_local.softtabstop = 0
    vim.opt_local.list = true
    vim.b.autoformat = false
  end,
  desc = "Apply Linux Kernel Style and disable autoformatting for C/H files",
})
]]
