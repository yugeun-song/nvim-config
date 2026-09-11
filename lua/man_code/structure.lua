-- Paint a man page's structure over nvim's bold marks.
--
-- syntax/man.vim classifies the page -- running header, section heading,
-- subheading, footer -- and a colorscheme can then say what each of those looks
-- like. None of it reaches the screen. nvim's man.lua paints roff's bold as
-- manBold extmarks at priority 4096, roff sets every heading in bold, and an
-- extmark at 4096 is above anything a syntax file can say. So DESCRIPTION and
-- the subheadings under it all came out as manBold, in one colour, and the
-- distinction the colorscheme drew was invisible.
--
-- The classification is cheap to redo -- it is four line shapes -- so it is
-- redone here as extmarks that sit above the bold ones.

local M = {}

local ns = vim.api.nvim_create_namespace("man_structure")

-- Above man.lua's 4096. Code blocks are painted by the sibling module at 5000
-- and never overlap a heading, so the two do not compete.
local PRIORITY = 5200

-- The parenthesis fix below sits above man.lua but below the code pass, so a
-- call written out inside an example keeps the parser's colours.
local CALL_PRIORITY = 4500

--- @param buf integer? buffer handle, defaults to the current one
--- @return integer lines painted
function M.highlight(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
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
      -- Exactly three columns of indent, which is what a subheading gets and
      -- body text does not.
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
      -- An option list entry: the name, and any aliases before it, but not the
      -- description that follows on the same line. Same shape syntax/man.vim
      -- matches, and it loses to manBold the same way everything else did.
      -- %S+ would swallow the comma that separates "-a, --all", and the
      -- continuation below would then never match, so the class stops at one.
      local from, e = line:find("^%s+[-+][^%s,]*")
      if e then
        from = line:find("%S")
        while true do
          local _, more = line:find("^,%s*[-+][^%s,]*", e + 1)
          if not more then break end
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

      -- Cross-references lose to manBold for the same reason the headings did:
      -- a page that sets open(2) in bold, as printf(1) does for printf(3),
      -- turned the one thing on the line that K can follow into ordinary
      -- emphasis. The pattern is the one syntax/man.vim uses, behind a plain
      -- substring test: a reference needs a parenthesis, most lines have none,
      -- and a page like cmake-modules(7) is 37,000 lines of asking.
      if line:find("(", 1, true) then
      for from, ref, to in line:gmatch("()([^%s()]+%(%d%a*%))()") do
        if #ref <= 64 then
          painted = painted + 1
          pcall(vim.api.nvim_buf_set_extmark, buf, ns, i - 1, from - 1, {
            end_row = i - 1,
            end_col = to - 1,
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

--- Extend a bold run over the parentheses that follow it.
---
--- man-pages writes a function as `.BR mmap ()`: the name is bold and the
--- empty parentheses are roman, because roff cannot change font mid-word
--- without splitting the macro. Rendered, that leaves mmap coloured and ()
--- the body colour, which reads as the page having missed a character. There
--- are 27 of them in mmap(2) alone.
---
--- Only an empty pair immediately after the run counts. `mmap(2)` is a
--- cross-reference and already blue, and `mmap(void addr[.length]` in a
--- SYNOPSIS is code the parser owns.
--- @param buf integer? buffer handle, defaults to the current one
--- @return integer runs extended
function M.close_calls(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local extended = 0

  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    local d = mark[4]
    if d.hl_group == "manBold" and d.end_row == mark[2] and d.end_col then
      local line = lines[mark[2] + 1]
      if line and line:sub(d.end_col + 1, d.end_col + 2) == "()" then
        extended = extended + 1
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, mark[2], d.end_col, {
          end_row = mark[2],
          end_col = d.end_col + 2,
          hl_group = "manBold",
          priority = CALL_PRIORITY,
          strict = false,
        })
      end
    end
  end
  return extended
end

function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf or 0, ns, 0, -1)
end

return M
