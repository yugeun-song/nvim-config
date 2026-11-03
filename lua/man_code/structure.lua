-- Re-mark a man page's structure above nvim's manBold extmarks (priority
-- 4096), which otherwise cover every group syntax/man.vim defines.

local M = {}

local ns = vim.api.nvim_create_namespace("man_structure")

-- Above man.lua's 4096; the code pass at 5000 never overlaps a heading.
local PRIORITY = 5200

-- Above man.lua, below the code pass, so a call inside an example keeps the
-- parser's colours.
local CALL_PRIORITY = 4500

--- @param buf integer? buffer handle, defaults to the current one
--- @return integer lines painted
function M.highlight(buf)
  if not buf or buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local last = #lines
  local painted = 0

  for i, line in ipairs(lines) do
    local group
    if i == 1 then
      group = "manHeader"
    elseif i == last then
      group = "manFooter"
    elseif line:match("^%S") then
      group = "manSectionHeading"
    elseif line:match("^   %S") then
      -- Three columns of indent is a subheading; body text has more.
      group = "manSubHeading"
    end

    if group and vim.trim(line) ~= "" then
      painted = painted + 1
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, i - 1, 0, {
        end_row = i - 1,
        end_col = #line,
        hl_group = group,
        priority = PRIORITY,
        strict = false,
      })
    elseif not group then
      -- Option name plus comma-separated aliases, not the description after them.
      -- [^%s,] keeps the comma in "-a, --all" for the continuation match.
      local from, e = line:find("^%s+[-+][^%s,]*")
      if e then
        from = line:find("%S")
        while true do
          local _, more = line:find("^,%s*[-+][^%s,]*", e + 1)
          if not more then
            break
          end
          e = more
        end
        if from and e >= from then
          painted = painted + 1
          pcall(vim.api.nvim_buf_set_extmark, buf, ns, i - 1, from - 1, {
            end_row = i - 1,
            end_col = e,
            hl_group = "manOptionDesc",
            priority = PRIORITY,
            strict = false,
          })
        end
      end

      -- syntax/man.vim's reference pattern, behind a substring test: most lines
      -- have no parenthesis and cmake-modules(7) has 37,000 lines.
      if line:find("(", 1, true) then
        for ref_from, ref, ref_to in line:gmatch("()([^%s()]+%(%d%a*%))()") do
          if #ref <= 64 then
            painted = painted + 1
            pcall(vim.api.nvim_buf_set_extmark, buf, ns, i - 1, ref_from - 1, {
              end_row = i - 1,
              end_col = ref_to - 1,
              hl_group = "manReference",
              priority = PRIORITY,
              strict = false,
            })
          end
        end
      end
    end
  end
  return painted
end

--- Extend a bold run over the `()` after it: man-pages writes `.BR mmap ()`, a bold name with roman parens.
--- `mmap(2)` (a reference) and `mmap(void addr[...]` (SYNOPSIS code) stay as they are.
--- @param buf integer? buffer handle, defaults to the current one
--- @return integer runs extended
function M.close_calls(buf)
  if not buf or buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local extended = 0

  for row, line in ipairs(lines) do
    local init = 1
    while true do
      local s = line:find("()", init, true)
      if not s then
        break
      end
      init = s + 2
      local col = s - 1
      for _, mark in
        ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, { row - 1, 0 }, { row - 1, col }, { details = true }))
      do
        local d = mark[4]
        if d and d.hl_group == "manBold" and d.end_row == row - 1 and d.end_col == col then
          extended = extended + 1
          pcall(vim.api.nvim_buf_set_extmark, buf, ns, row - 1, col, {
            end_row = row - 1,
            end_col = col + 2,
            hl_group = "manBold",
            priority = CALL_PRIORITY,
            strict = false,
          })
        end
      end
    end
  end
  return extended
end

function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf or 0, ns, 0, -1)
end

return M
