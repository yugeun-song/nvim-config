local function exact_search_content(content)
  local ct = vim.fn.getcmdtype()
  if ct == "/" or ct == "?" then
    return nil
  end
  local sc = vim.fn.searchcount({ maxcount = 0, timeout = 500, recompute = true })
  if type(sc) ~= "table" or (sc.total or 0) == 0 or sc.incomplete ~= 0 then
    return nil
  end
  local first = (content and content[1]) or {}
  local chunk = { first[1] or 0, string.format("[%d/%d]", sc.current, sc.total) }
  if first[3] ~= nil then
    chunk[3] = first[3]
  end
  return { chunk }
end

local function patch_search_count()
  local ok, msg = pcall(require, "noice.ui.msg")
  if not ok or msg.__exact_search_count or type(msg.on_show) ~= "function" then
    return
  end
  msg.__exact_search_count = true
  local orig = msg.on_show
  msg.on_show = function(event, kind, content, replace_last)
    if kind == msg.kinds.search_count then
      local rewritten_ok, rewritten = pcall(exact_search_content, content)
      if rewritten_ok and rewritten then
        content = rewritten
      end
    end
    return orig(event, kind, content, replace_last)
  end
end

return {
  "folke/noice.nvim",
  opts = function(_, opts)
    vim.schedule(patch_search_count)
    return opts
  end,
}
