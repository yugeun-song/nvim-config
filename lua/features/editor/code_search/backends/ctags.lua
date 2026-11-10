-- Neovim's tag search over the buffer's 'tags' files (those <C-]> reads), listed as <<name>> and the tag's line.
local search_job = require("features.editor.code_search.search_job")

local M = {
  name = "ctags",
  label = "ctags",
  kinds = { { name = "tag", label = "tag name" } },
}

function M.offer(ctx)
  local files = vim.api.nvim_buf_call(ctx.buf, vim.fn.tagfiles)

  if #files == 0 then
    return nil, ("no tags file from %s through 'tags'"):format(vim.fn.fnamemodify(ctx.dir, ":~"))
  end

  local first = vim.fn.fnamemodify(files[1], ":p:~:.")

  return #files > 1 and ("%s and %d more"):format(first, #files - 1) or first
end

-- A tag's address is a line number or a search pattern of ctags' own form: /^literal text$/ with / and \ escaped.
local function line_of(tag, lines)
  local number = tonumber(tag.line) or tonumber(tostring(tag.cmd):match("^(%d+)"))

  if number then
    return number
  end

  local body = tostring(tag.cmd):match("^/(.*)/$") or tostring(tag.cmd):match("^%?(.*)%?$")

  if not body then
    return nil
  end

  local head = body:sub(1, 1) == "^"
  local tail = body:sub(-1) == "$" and body:sub(-2, -2) ~= "\\"

  body = body:sub(head and 2 or 1, tail and -2 or -1):gsub("\\(.)", "%1")
  for i, line in ipairs(lines) do
    local hit

    if head and tail then
      hit = line == body
    elseif head then
      hit = line:sub(1, #body) == body
    elseif tail then
      hit = line:sub(-#body) == body
    else
      hit = line:find(body, 1, true) ~= nil
    end

    if hit then
      return i
    end
  end
end

local function file_lines(cache, path)
  if not cache[path] then
    local ok, lines = pcall(vim.fn.readfile, path)

    cache[path] = ok and lines or {}
  end

  return cache[path]
end

-- A plain name matches whole and case-sensitively (binary search on sorted tags); anything else is a Vim regex.
local function taglist(pattern, ctx)
  local regex = pattern:match("^[%w_]+$") and ("^" .. pattern .. "$") or pattern
  local ok, tags

  vim.api.nvim_buf_call(ctx.buf, function()
    local saved = vim.bo.tagcase

    vim.bo.tagcase = "match"
    ok, tags = pcall(vim.fn.taglist, regex, ctx.file)
    vim.bo.tagcase = saved
  end)

  if not ok then
    return {}, tostring(tags)
  end

  return tags
end

function M.search(_, pattern, ctx, done)
  if not vim.api.nvim_buf_is_valid(ctx.buf) then
    return done(nil, "ctags: the buffer is gone", vim.log.levels.ERROR)
  end

  local tags, err = taglist(pattern, ctx)

  if err then
    return done(nil, "ctags: " .. err, vim.log.levels.ERROR)
  end

  local cache, entries = {}, {}
  local cwd = vim.fn.getcwd()

  for i = 1, math.min(#tags, search_job.MAX_RESULTS) do
    local tag = tags[i]
    local path = vim.fn.isabsolutepath(tag.filename) == 1 and tag.filename or vim.fs.joinpath(cwd, tag.filename)

    path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))

    local lines = file_lines(cache, path)
    local lnum = line_of(tag, lines)
    local text = lnum and lines[lnum] or tostring(tag.cmd)

    entries[#entries + 1] = {
      filename = path,
      lnum = lnum or 1,
      text = ("<<%s>> %s"):format(tag.name, vim.trim(text)),
    }
  end

  if #tags > search_job.MAX_RESULTS then
    return done(
      entries,
      ("ctags: only the first %d of %d tags; narrow the pattern"):format(search_job.MAX_RESULTS, #tags),
      vim.log.levels.WARN
    )
  end

  done(entries)
end

return M
