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

vim.api.nvim_create_autocmd("LspAttach", {
  group = augroup("kernel_diagnostic_mute"),
  callback = function(args)
    if vim.g.kernel_diag_mute_enabled == false then
      return
    end
    local ft = vim.bo[args.buf].filetype
    if ft ~= "c" and ft ~= "cpp" and ft ~= "h" then
      return
    end
    if vim.fn.findfile(".nvim-diag-off", ".;") == "" then
      return
    end
    vim.diagnostic.enable(false, { bufnr = args.buf })
  end,
  desc = "Mute LSP diagnostics in C/C++/H buffers under a project rooted at .nvim-diag-off",
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = augroup("kernel_clangd_off"),
  callback = function(args)
    if vim.g.kernel_clangd_off_enabled == false then
      return
    end
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client or client.name ~= "clangd" then
      return
    end
    local bufname = vim.api.nvim_buf_get_name(args.buf)
    local start = bufname ~= "" and vim.fn.fnamemodify(bufname, ":p:h") or vim.fn.getcwd()
    if vim.fn.findfile(".nvim-clangd-off", start .. ";") == "" then
      return
    end
    local client_id = client.id
    vim.schedule(function()
      pcall(vim.lsp.stop_client, client_id, false)
    end)
  end,
  desc = "Stop clangd gracefully under a project rooted at .nvim-clangd-off (upward from buffer file)",
})
