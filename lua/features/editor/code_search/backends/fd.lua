-- fd for file names, only without rg; same root and settings as the Snacks files picker.
local context = require("features.editor.code_search.buffer_context")
local search_job = require("features.editor.code_search.search_job")

local M = {
  name = "fd",
  label = "fd",
  kinds = { { name = "file", label = "file name regex" } },
}

local function program()
  return vim.fn.executable("fd") == 1 and "fd" or vim.fn.executable("fdfind") == 1 and "fdfind" or nil
end

function M.offer(ctx)
  if vim.fn.executable("rg") == 1 then
    return nil, "rg is on PATH, and ripgrep searches instead"
  end

  if not program() then
    return nil, "fd is not on PATH"
  end

  return "file names under " .. vim.fn.fnamemodify(context.root(ctx), ":~")
end

function M.search(_, pattern, ctx, done)
  local root = context.root(ctx)
  local options = context.picker_options("files")
  local argv = { program(), "--type", "f", "--type", "l", "--color=never", "--absolute-path", "--exclude", ".git" }

  for _, name in ipairs(options.exclude or {}) do
    vim.list_extend(argv, { "--exclude", name })
  end

  if options.hidden then
    argv[#argv + 1] = "--hidden"
  end

  if options.ignored then
    argv[#argv + 1] = "--no-ignore"
  end

  if options.follow then
    argv[#argv + 1] = "--follow"
  end

  vim.list_extend(argv, { "--", pattern, root })

  return search_job.lines(argv, root, function(lines, result, truncated)
    if result.code ~= 0 and not truncated then
      return done(nil, search_job.failure("fd", result), vim.log.levels.ERROR)
    end

    local entries = {}

    for _, line in ipairs(lines) do
      if line ~= "" then
        entries[#entries + 1] = { filename = vim.fs.normalize(line), lnum = 1, col = 0, text = "", file_only = true }
      end
    end

    if truncated then
      return done(entries, ("fd: only the first %d files; narrow the pattern"):format(#entries), vim.log.levels.WARN)
    end

    done(entries)
  end)
end

return M
