-- cscope through :Cscope find: the database, filter and picker of the <leader>i keys.
local M = {
  name = "cscope",
  label = "cscope",
  kinds = {
    { name = "s", label = "symbol" },
    { name = "g", label = "global definition" },
    { name = "c", label = "functions calling" },
    { name = "d", label = "functions called by" },
    { name = "t", label = "text" },
    { name = "e", label = "egrep pattern" },
    { name = "f", label = "file" },
    { name = "i", label = "files including" },
    { name = "a", label = "assignments to" },
  },
}

-- The database cscope_maps' get_result wrapper reads for this buffer.
local function database(ctx)
  return vim.fs.find("cscope.out", { upward = true, path = ctx.dir, type = "file" })[1]
end

function M.offer(ctx)
  if vim.fn.executable("cscope") == 0 then
    return nil, "cscope is not on PATH"
  end

  local found = database(ctx)

  if not found then
    return nil, ("no cscope.out in %s or above"):format(vim.fn.fnamemodify(ctx.dir, ":~"))
  end

  return vim.fn.fnamemodify(found, ":~:.")
end

function M.open(kind, pattern, ctx)
  if vim.api.nvim_win_is_valid(ctx.win) and vim.api.nvim_win_get_buf(ctx.win) == ctx.buf then
    vim.api.nvim_set_current_win(ctx.win)
  end

  local ok, err = pcall(vim.api.nvim_cmd, { cmd = "Cscope", args = { "find", kind.name, pattern } }, {})

  if not ok then
    require("features.editor.code_search.search_job").notify("cscope: " .. tostring(err), vim.log.levels.ERROR)
  end
end

return M
