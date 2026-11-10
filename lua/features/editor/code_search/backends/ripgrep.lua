-- ripgrep under <leader>/'s root with the Snacks grep settings; index databases are skipped.
local context = require("features.editor.code_search.buffer_context")
local search_job = require("features.editor.code_search.search_job")

local M = {
  name = "rg",
  label = "ripgrep",
  kinds = { { name = "text", label = "regex" } },
}

local INDEX_FILES = {
  "tags",
  "TAGS",
  "cscope.out",
  "cscope.in.out",
  "cscope.po.out",
  "cscope.files",
  "GTAGS",
  "GRTAGS",
  "GPATH",
}

function M.offer(ctx)
  if vim.fn.executable("rg") == 0 then
    return nil, "rg is not on PATH"
  end

  return "under " .. vim.fn.fnamemodify(context.root(ctx), ":~")
end

local function argv(pattern, root)
  local options = context.picker_options("grep")
  local args = {
    "rg",
    "--color=never",
    "--no-heading",
    "--with-filename",
    "--line-number",
    "--column",
    "--null",
    "--smart-case",
    "--max-columns=500",
    "--max-columns-preview",
    "--glob=!.git",
    "--glob=!.bare",
    options.hidden and "--hidden" or "--no-hidden",
  }

  for _, name in ipairs(vim.list_extend(vim.deepcopy(options.exclude or {}), INDEX_FILES)) do
    args[#args + 1] = "--glob=!" .. name
  end

  if options.ignored then
    args[#args + 1] = "--no-ignore"
  end

  if options.follow then
    args[#args + 1] = "--follow"
  end

  return vim.list_extend(args, { "--", pattern, root })
end

function M.search(_, pattern, ctx, done)
  local root = context.root(ctx)

  return search_job.lines(argv(pattern, root), root, function(lines, result, truncated)
    local entries = {}

    for _, line in ipairs(lines) do
      local path, lnum, col, text = line:match("^(.-)%z(%d+):(%d+):(.*)$")

      if path then
        entries[#entries + 1] = {
          filename = vim.fs.normalize(path),
          lnum = tonumber(lnum),
          col = tonumber(col) - 1,
          text = vim.trim(text),
        }
      end
    end

    if truncated then
      return done(entries, ("rg: only the first %d hits; narrow the pattern"):format(#entries), vim.log.levels.WARN)
    end

    -- 1 is no match; 2 is an error, which may still come with the hits of the files rg could read.
    if result.code ~= 0 and result.code ~= 1 and #entries == 0 then
      return done(nil, search_job.failure("rg", result), vim.log.levels.ERROR)
    end

    done(entries)
  end)
end

return M
