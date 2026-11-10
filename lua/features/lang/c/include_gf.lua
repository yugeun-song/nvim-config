-- gf on an #include line opens the header the project's own tools place: clangd with a project compile
-- database, else a tags file entry, cscope.out or cscope.files line (a picker when several match), else the
-- built-in gf.
local M = {}

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

local function lsp_include(buf, done)
  local method = "textDocument/definition"

  if
    not project_compile_db(vim.api.nvim_buf_get_name(buf))
    or #vim.lsp.get_clients({ bufnr = buf, method = method }) == 0
  then
    return done()
  end

  local finished = false
  local timer = assert(vim.uv.new_timer())

  local function finish(path, root)
    if not finished then
      finished = true
      timer:close()
      done(path, root)
    end
  end

  local cancel = vim.lsp.buf_request_all(buf, method, function(client)
    return vim.lsp.util.make_position_params(0, client.offset_encoding)
  end, function(results)
    for id, res in pairs(results) do
      local loc = type(res.result) == "table" and (res.result[1] or res.result)
      local uri = loc and (loc.uri or loc.targetUri)

      if uri then
        local client = vim.lsp.get_client_by_id(id)

        return finish(vim.uri_to_fname(uri), client and client.root_dir)
      end
    end

    finish()
  end)

  timer:start(
    2000,
    0,
    vim.schedule_wrap(function()
      pcall(cancel)
      finish()
    end)
  )
end

local function indexed_includes(buf, spelled)
  local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(buf))
  local suffix = "/" .. spelled
  local found, seen = {}, {}

  local function add(path, base)
    if base and vim.fn.isabsolutepath(path) == 0 then
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
    local res = vim.system({ "cscope", "-d", "-L", "-f", db, "-7", pattern }, { cwd = base, text = true }):wait(2000)

    for line in vim.gsplit(res.stdout or "", "\n", { trimempty = true }) do
      add(line:match("^%S+"), base)
    end

    return found
  end

  -- Regular files only: a FIFO would never end.
  local list = vim.fs.find("cscope.files", { upward = true, path = dir, type = "file" })[1]
  local fd = list and io.open(list, "rb")

  if not fd then
    return found
  end

  local text = fd:read("*a")

  fd:close()
  local base, init = vim.fs.dirname(list), 1

  while true do
    local s, e = text:find(spelled, init, true)

    if not s then
      break
    end

    init = e + 1
    local after, before = text:byte(e + 1), text:byte(s - 1)

    if
      (not after or after == 10 or after == 13 or after == 34)
      and (not before or before == 47 or before == 10 or before == 34)
    then
      local ls = s

      while ls > 1 and text:byte(ls - 1) ~= 10 do
        ls = ls - 1
      end

      local line = text:sub(ls, e):gsub('^"', "")

      if line:sub(1, 1) ~= "-" then
        add(line, base)
      end
    end
  end

  return found
end

local SYSTEM_DIRS = {
  "^/usr/",
  "/usr/include/",
  "^/opt/homebrew/",
  "^/nix/store/",
  "^/Library/Developer/",
  "^/Applications/Xcode[^/]*%.app/",
  "/lib/clang/%d+/include/",
  "/lib/gcc/",
  "/Windows Kits/",
  "/Microsoft Visual Studio/",
}

local function system_header(path)
  for _, pattern in ipairs(SYSTEM_DIRS) do
    if path:find(pattern) then
      return true
    end
  end

  return false
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

local function include_targets(buf, spelled, quoted, path, root)
  local file = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))

  if path then
    local real = vim.fs.normalize(vim.uv.fs_realpath(path) or path)
    local real_root = root and vim.uv.fs_realpath(root)

    if (real_root and vim.fs.relpath(vim.fs.normalize(real_root), real)) or system_header(real) then
      return { path }
    end
  end

  local here = vim.fs.joinpath(vim.fs.dirname(file), spelled)

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

local function builtin_gf()
  local ok, err = pcall(vim.api.nvim_command, "normal! gf")

  if not ok then
    vim.api.nvim_echo({ { tostring(err):match("E%d+:.*") or tostring(err), "ErrorMsg" } }, true, {})
  end
end

function M.map(buf)
  vim.keymap.set("n", "gf", function()
    local delim, spelled = vim.api.nvim_get_current_line():match('^%s*#%s*include%w*%s*([<"])([^>"]+)[>"]')

    if not spelled then
      return builtin_gf()
    end

    local win = vim.api.nvim_get_current_win()
    local cursor = vim.api.nvim_win_get_cursor(win)

    lsp_include(buf, function(path, root)
      if
        vim.api.nvim_get_current_win() ~= win
        or vim.api.nvim_win_get_buf(win) ~= buf
        or not vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor)
      then
        return
      end

      local targets = include_targets(buf, spelled, delim == '"', path, root)

      local function open(target)
        if target then
          vim.cmd.edit(vim.fn.fnameescape(target))
        end
      end

      if #targets == 1 then
        open(targets[1])
      elseif #targets > 1 then
        vim.ui.select(targets, { prompt = spelled }, open)
      else
        builtin_gf()
      end
    end)
  end, { buffer = buf, desc = "Go to file; #include through clangd, tags or cscope" })
end

return M
