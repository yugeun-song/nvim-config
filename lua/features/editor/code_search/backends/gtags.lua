-- GNU Global from the buffer's directory (global -x, -rx, -sx, -gx, -Px).
local search_job = require("features.editor.code_search.search_job")

local M = {
  name = "gtags",
  label = "gtags",
  kinds = {
    { name = "definition", label = "definitions" },
    { name = "reference", label = "references", flag = "-r" },
    { name = "symbol", label = "symbols without a definition", flag = "-s" },
    { name = "grep", label = "grep", flag = "-g" },
    { name = "path", label = "paths", flag = "-P" },
  },
}

local ROOT_PATIENCE_MS = 2000

function M.offer(ctx)
  if vim.fn.executable("global") == 0 then
    return nil, "global is not on PATH"
  end

  local ok, result = pcall(function()
    return vim.system({ "global", "-p" }, { cwd = ctx.dir, text = true }):wait(ROOT_PATIENCE_MS)
  end)

  if not ok or result.code ~= 0 then
    return nil, ("no GTAGS for %s"):format(vim.fn.fnamemodify(ctx.dir, ":~"))
  end

  return vim.fn.fnamemodify(vim.trim(result.stdout), ":~")
end

function M.search(kind, pattern, ctx, done)
  local argv = { "global", "--result=grep", "-a" }

  if kind.flag then
    argv[#argv + 1] = kind.flag
  end

  vim.list_extend(argv, { "--", pattern })

  return search_job.lines(argv, ctx.dir, function(lines, result, truncated)
    if result.code ~= 0 and not truncated then
      return done(nil, search_job.failure("gtags", result), vim.log.levels.ERROR)
    end

    local entries = {}

    for _, line in ipairs(lines) do
      local path, lnum, text = line:match("^(.-):(%d+):(.*)$")

      if path then
        entries[#entries + 1] = {
          filename = vim.fs.normalize(path),
          lnum = tonumber(lnum),
          text = vim.trim(text),
          file_only = kind.name == "path",
        }
      end
    end

    if truncated then
      return done(entries, ("gtags: only the first %d hits; narrow the pattern"):format(#entries), vim.log.levels.WARN)
    end

    done(entries)
  end)
end

return M
