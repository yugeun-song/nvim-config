local M = {}

local function leading_spaces(line)
  local lead = #line:match("^ *")
  if line:byte(lead + 1) == 9 then
    return nil
  end
  return lead
end

local function target(step, col, count)
  local lead = leading_spaces(vim.api.nvim_get_current_line())
  local width = vim.fn.shiftwidth()
  if not lead or width < 2 then
    return nil
  end
  if step > 0 then
    if col >= lead then
      return nil
    end
    while count > 0 and col < lead do
      col = math.min(lead, (math.floor(col / width) + 1) * width)
      count = count - 1
    end
  else
    if col == 0 or col > lead then
      return nil
    end
    while count > 0 and col > 0 do
      col = math.floor((col - 1) / width) * width
      count = count - 1
    end
  end
  return col, count
end

local function motion(step, key, count_keys)
  return function()
    local col, rest = target(step, vim.fn.col(".") - 1, count_keys and vim.v.count1 or 1)
    if not col then
      return key
    end
    local keys = ("<Cmd>call cursor(0, %d)<CR>"):format(col + 1)
    if count_keys and rest > 0 then
      keys = keys .. rest .. key
    end
    return keys
  end
end

function M.setup()
  for _, map in ipairs({ { "l", 1 }, { "<Right>", 1 }, { "h", -1 }, { "<Left>", -1 } }) do
    vim.keymap.set(
      { "n", "x" },
      map[1],
      motion(map[2], map[1], true),
      { expr = true, desc = "Move by indent stops in leading spaces" }
    )
  end
  for _, map in ipairs({ { "<Right>", 1 }, { "<Left>", -1 } }) do
    vim.keymap.set(
      "i",
      map[1],
      motion(map[2], map[1], false),
      { expr = true, desc = "Move by indent stops in leading spaces" }
    )
  end
end

return M
