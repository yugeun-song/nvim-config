-- Parts adapted from https://github.com/LazyVim/LazyVim (Apache-2.0). See THIRD-PARTY-NOTICES.
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

local function indents_with_tabs(buf)
  local tabs, spaces = 0, 0
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, 2000, false)) do
    if line:find("^\t") then
      tabs = tabs + 1
    elseif line:find("^  ") then
      spaces = spaces + 1
    end
  end
  return tabs > spaces
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
    elseif indents_with_tabs(args.buf) then
      opt.tabstop = 8
      opt.shiftwidth = 8
      opt.softtabstop = 8
      opt.expandtab = false
    else
      opt.tabstop = 8
      opt.shiftwidth = 4
      opt.softtabstop = 4
      opt.expandtab = true
    end
    opt.list = true
    vim.b.autoformat = false
  end,
  desc = "Indent C/C++ per .clang-format, else 8-col tabs if the file uses tabs, else 4 spaces; .editorconfig still wins",
})

local function project_compile_db(file)
  for dir in vim.fs.parents(file) do
    for _, name in ipairs({ "compile_commands.json", "compile_flags.txt" }) do
      if vim.uv.fs_stat(dir .. "/" .. name) or vim.uv.fs_stat(dir .. "/build/" .. name) then
        return true
      end
    end
  end
  return false
end

local function lsp_include(buf)
  local method = "textDocument/definition"
  if
    not project_compile_db(vim.api.nvim_buf_get_name(buf))
    or #vim.lsp.get_clients({ bufnr = buf, method = method }) == 0
  then
    return nil
  end
  local results = vim.lsp.buf_request_sync(buf, method, function(client)
    return vim.lsp.util.make_position_params(0, client.offset_encoding)
  end, 2000)
  for id, res in pairs(results or {}) do
    local loc = type(res.result) == "table" and (res.result[1] or res.result)
    local uri = loc and (loc.uri or loc.targetUri)
    if uri then
      local client = vim.lsp.get_client_by_id(id)
      return vim.uri_to_fname(uri), client and client.root_dir
    end
  end
end

local function indexed_includes(buf, spelled)
  local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(buf))
  local suffix = "/" .. spelled
  local found, seen = {}, {}
  local function add(path, base)
    if base and path:sub(1, 1) ~= "/" then
      path = base .. "/" .. path
    end
    path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
    if not seen[path] and vim.endswith(path, suffix) and vim.uv.fs_stat(path) then
      seen[path] = true
      found[#found + 1] = path
    end
  end
  local tagcase = vim.bo[buf].tagcase
  vim.bo[buf].tagcase = "match"
  local ok, tags = pcall(vim.fn.taglist, "^" .. vim.fn.escape(vim.fs.basename(spelled), [[\.*$^~[]]) .. "$")
  vim.bo[buf].tagcase = tagcase
  for _, tag in ipairs(ok and tags or {}) do
    if tag.kind == "F" or tag.kind == "file" then
      add(tag.filename)
    end
  end
  if #found > 0 then
    return found
  end
  local db = vim.fs.find("cscope.out", { upward = true, path = dir })[1]
  if db and vim.fn.executable("cscope") == 1 then
    local base = vim.fs.dirname(db)
    local pattern = spelled:gsub("[^%w/_-]", ".")
    local res = vim.system({ "cscope", "-d", "-L", "-f", db, "-7", pattern }, { cwd = base, text = true }):wait(3000)
    for line in vim.gsplit(res.stdout or "", "\n", { trimempty = true }) do
      add(line:match("^%S+"), base)
    end
    return found
  end
  local list = vim.fs.find("cscope.files", { upward = true, path = dir })[1]
  if list then
    for line in io.lines(list) do
      line = line:gsub('^"(.*)"$', "%1")
      if line:sub(1, 1) ~= "-" and vim.endswith("/" .. line, suffix) then
        add(line, vim.fs.dirname(list))
      end
    end
  end
  return found
end

local function system_header(path)
  return path:find("^/usr/") or path:find("/lib/clang/%d+/include/") or path:find("/lib/gcc/")
end

local function shared_dirs(a, b)
  local n = 0
  for i = 1, math.min(#a, #b) do
    if a:byte(i) ~= b:byte(i) then
      break
    elseif a:byte(i) == 47 then
      n = n + 1
    end
  end
  return n
end

local function include_targets(buf, spelled, quoted)
  local file = vim.api.nvim_buf_get_name(buf)
  local path, root = lsp_include(buf)
  if path then
    local real, real_root = vim.uv.fs_realpath(path) or path, root and vim.uv.fs_realpath(root)
    if (real_root and vim.startswith(real, real_root .. "/")) or system_header(real) then
      return { path }
    end
  end
  local here = vim.fs.dirname(file) .. "/" .. spelled
  if quoted and vim.uv.fs_stat(here) then
    return { here }
  end
  local found = indexed_includes(buf, spelled)
  if #found == 0 and path then
    found[1] = path
  end
  local rank = {}
  for i, p in ipairs(found) do
    rank[p] = { shared_dirs(p, file), i }
  end
  table.sort(found, function(a, b)
    local ra, rb = rank[a], rank[b]
    if ra[1] ~= rb[1] then
      return ra[1] > rb[1]
    end
    return ra[2] < rb[2]
  end)
  return found
end

vim.api.nvim_create_autocmd("FileType", {
  group = augroup("include_gf"),
  pattern = { "c", "cpp", "objc", "objcpp", "cuda", "asm", "ld" },
  callback = function(args)
    vim.keymap.set("n", "gf", function()
      local delim, spelled = vim.api.nvim_get_current_line():match('^%s*#%s*include%w*%s*([<"])([^>"]+)[>"]')
      local targets = spelled and include_targets(args.buf, spelled, delim == '"') or {}
      local function open(path)
        if path then
          vim.cmd("edit " .. vim.fn.fnameescape(path))
        end
      end
      if #targets == 1 then
        open(targets[1])
      elseif #targets > 1 then
        vim.ui.select(targets, { prompt = spelled }, open)
      else
        local ok, err = pcall(vim.cmd, "normal! gf")
        if not ok then
          vim.api.nvim_echo({ { tostring(err):match("E%d+:.*") or tostring(err), "ErrorMsg" } }, true, {})
        end
      end
    end, { buffer = args.buf, desc = "Go to file; #include through clangd, tags or cscope" })
  end,
  desc = "gf on #include opens the header the project's compile database, tags or cscope place in the project",
})

local cscope_loaded = {}
vim.api.nvim_create_autocmd("BufRead", {
  group = augroup("cscope_auto_load"),
  pattern = { "*.c", "*.h", "*.S" },
  callback = function()
    local db = vim.fn.findfile("cscope.out", ".;")
    if type(db) ~= "string" or db == "" then
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
    pcall(vim.api.nvim_command, "silent! Cs db a " .. vim.fn.fnameescape(abs) .. "::@")
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

vim.api.nvim_create_autocmd("FileType", {
  group = augroup("wrap_spell"),
  pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
  callback = function()
    vim.opt_local.wrap = true
  end,
  desc = "Replace LazyVim's wrap_spell: wrap prose buffers but leave spell off",
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = augroup("claude_prompt"),
  pattern = "claude-prompt-*.md",
  callback = function(args)
    vim.schedule(function()
      vim.lsp.buf_detach_client(args.buf, args.data.client_id)
    end)
  end,
  desc = "Keep LSP clients off the prompt file Claude Code opens on Ctrl+G",
})
