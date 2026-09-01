local function augroup(name)
  return vim.api.nvim_create_augroup("lazyvim_" .. name, { clear = true })
end

local clang_format_style_indent = {
  llvm = 2,
  google = 2,
  chromium = 2,
  mozilla = 2,
  webkit = 4,
  microsoft = 4,
  gnu = 2,
}

local function clang_format_indent(bufname)
  if bufname == "" then
    return nil
  end
  local found = vim.fs.find({ ".clang-format", "_clang-format" }, {
    upward = true,
    path = vim.fs.dirname(bufname),
    type = "file",
  })[1]
  if not found then
    return nil
  end
  local indent, tab_width, use_tab, based
  for line in io.lines(found) do
    if line:match("^%-%-%-") and (indent or use_tab or based) then
      break
    end
    local key, value = line:match("^%s*([%w_]+)%s*:%s*([^#]*)")
    if key then
      value = vim.trim(value)
      if key == "IndentWidth" then
        indent = tonumber(value)
      elseif key == "TabWidth" then
        tab_width = tonumber(value)
      elseif key == "UseTab" then
        use_tab = value
      elseif key == "BasedOnStyle" then
        based = value:lower()
      end
    end
  end
  indent = indent or clang_format_style_indent[based] or 2
  return {
    shiftwidth = indent,
    tabstop = tab_width or 8,
    expandtab = use_tab == nil or use_tab == "Never",
  }
end

vim.api.nvim_create_autocmd("FileType", {
  group = augroup("c_cpp_indent"),
  pattern = { "c", "cpp" },
  callback = function(args)
    local opt = vim.opt_local
    local style = clang_format_indent(vim.api.nvim_buf_get_name(args.buf))
    if style then
      opt.tabstop = style.tabstop
      opt.shiftwidth = style.shiftwidth
      opt.softtabstop = style.shiftwidth
      opt.expandtab = style.expandtab
    else
      opt.tabstop = 4
      opt.shiftwidth = 4
      opt.softtabstop = 4
      opt.expandtab = true
    end
    opt.list = true
    vim.b.autoformat = false
  end,
  desc = "Indent C/C++ with 4 spaces unless .clang-format says otherwise; .editorconfig still wins",
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
