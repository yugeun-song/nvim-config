-- What a code search starts from: buffer, file, directory, C family or not, and the search root.
local M = {}

-- C, C++, CUDA, assembly and linker scripts (headers are c or cpp); extensions cover other filetype names.
local C_FILETYPES = {
  c = true,
  cpp = true,
  cuda = true,
  asm = true,
  nasm = true,
  masm = true,
  ld = true,
}

local C_EXTENSIONS = {
  c = true,
  h = true,
  cc = true,
  cpp = true,
  cxx = true,
  hh = true,
  hpp = true,
  hxx = true,
  inl = true,
  ipp = true,
  tcc = true,
  i = true,
  ii = true,
  s = true,
  S = true,
  sx = true,
  asm = true,
  lds = true,
  cu = true,
  cuh = true,
}

local function window_of(buf)
  local current = vim.api.nvim_get_current_win()

  if vim.api.nvim_win_get_buf(current) == buf then
    return current
  end

  return vim.fn.win_findbuf(buf)[1] or current
end

function M.of(buf)
  buf = buf and buf ~= 0 and buf or vim.api.nvim_get_current_buf()

  local name = vim.api.nvim_buf_get_name(buf)
  local file = vim.bo[buf].buftype == "" and name ~= "" and vim.fs.normalize(vim.fn.fnamemodify(name, ":p")) or nil
  local cwd = vim.fs.normalize(vim.fn.getcwd())
  local extension = file and file:match("%.([^./]+)$")

  return {
    buf = buf,
    win = window_of(buf),
    file = file,
    dir = file and vim.fs.dirname(file) or cwd,
    cwd = cwd,
    filetype = vim.bo[buf].filetype,
    c_family = file ~= nil and (C_FILETYPES[vim.bo[buf].filetype] or C_EXTENSIONS[extension] or false),
  }
end

-- LazyVim's root for a file, the one <leader>/ greps; the working directory for a buffer without one.
function M.root(ctx)
  if not ctx.file then
    return ctx.cwd
  end

  local ok, root = pcall(function()
    return LazyVim.root.get({ buf = ctx.buf, normalize = true })
  end)

  return ok and type(root) == "string" and root or ctx.cwd
end

-- hidden, ignored, follow and exclude as the Snacks picker source has them (lua/plugins/editor/pickers.lua).
function M.picker_options(source)
  local ok, options = pcall(function()
    return require("snacks.picker.config").get({ source = source })
  end)

  return ok and type(options) == "table" and options or {}
end

return M
