local M = {}

-- dap-view annotates only treesitter "definition" captures, i.e. declaration
-- lines; every use stays bare, and a macro argument list is all uses.  Values
-- go at end of line, not beside each identifier: inline text pushes the code
-- sideways and splits `type->cnt` into `type` and a distant `->cnt`.
local ns = vim.api.nvim_create_namespace("dbg_inline")

M.enabled = true
M.max_value = 24
M.max_line = 90

local function dapview_ns()
  local ok, globals = pcall(require, "dap-view.globals")
  return ok and globals.NAMESPACE_VT or nil
end

local function shorten(value)
  value = tostring(value or ""):gsub("%s+", " ")
  if vim.fn.strdisplaywidth(value) <= M.max_value then
    return value
  end
  return vim.fn.strcharpart(value, 0, M.max_value - 1) .. "~"
end

function M.clear(buf)
  if buf then
    pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
    return
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) then
      pcall(vim.api.nvim_buf_clear_namespace, b, ns, 0, -1)
    end
  end
end

function M.render(session, values)
  M.clear()
  if not M.enabled or not session or not values or vim.tbl_isempty(values) then
    return
  end
  local frame = session.current_frame
  local path = frame and frame.source and frame.source.path
  if not path then
    return
  end
  local buf = vim.fn.bufnr(path, false)
  if buf == -1 or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local wins = vim.fn.win_findbuf(buf)
  if #wins == 0 then
    return
  end
  local first, last = math.huge, 0
  for _, win in ipairs(wins) do
    vim.api.nvim_win_call(win, function()
      first = math.min(first, vim.fn.line("w0") - 1)
      last = math.max(last, vim.fn.line("w$"))
    end)
  end
  if first > last then
    return
  end

  local taken = {}
  local other = dapview_ns()
  if other then
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, other, { first, 0 }, { last, -1 }, {})) do
      taken[mark[2] .. ":" .. mark[3]] = true
    end
  end

  local ft = vim.bo[buf].filetype
  local lang = ft ~= "" and vim.treesitter.language.get_lang(ft) or nil
  if not lang then
    return
  end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
  if not ok or not parser then
    return
  end
  local tree = (parser:parse(false) or {})[1]
  if not tree then
    return
  end

  -- Names dap-view already shows on a line are not repeated.
  local shown_by_dapview = {}
  for key in pairs(taken) do
    local row = tonumber(key:match("^(%d+):"))
    if row then
      shown_by_dapview[row] = true
    end
  end

  local per_line = {}
  local function visit(node)
    for child in node:iter_children() do
      local srow, _, erow = child:range()
      if srow <= last and erow >= first then
        if child:type() == "identifier" and srow == erow then
          local name = vim.treesitter.get_node_text(child, buf)
          if values[name] then
            per_line[srow] = per_line[srow] or { order = {}, seen = {} }
            local bucket = per_line[srow]
            if not bucket.seen[name] then
              bucket.seen[name] = true
              bucket.order[#bucket.order + 1] = name
            end
          end
        end
        visit(child)
      end
    end
  end
  visit(tree:root())

  for row, bucket in pairs(per_line) do
    local parts = {}
    for _, name in ipairs(bucket.order) do
      -- a declaration line already carries the value dap-view put there
      if not (shown_by_dapview[row] and #bucket.order == 1) then
        parts[#parts + 1] = name .. " = " .. shorten(values[name])
      end
    end
    if #parts > 0 then
      local text = table.concat(parts, "   ")
      if vim.fn.strdisplaywidth(text) > M.max_line then
        text = vim.fn.strcharpart(text, 0, M.max_line - 1) .. "~"
      end
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
        virt_text = { { "   " .. text, "DbgInlineValue" } },
        virt_text_pos = "eol",
        hl_mode = "combine",
        priority = 150,
      })
    end
  end
end

function M.toggle(state)
  if state == nil then
    M.enabled = not M.enabled
  else
    M.enabled = state
  end
  if not M.enabled then
    M.clear()
  end
  require("dbg.notify").info("Inline values " .. (M.enabled and "on" or "off"))
end

return M
