return {
  "nvim-treesitter/nvim-treesitter",
  opts = { ensure_installed = { "asm", "c", "cpp", "linkerscript", "devicetree" } },
  init = function()
    -- Powers #at-line-start? in after/queries/asm/injections.scm: the cpp
    -- injection only fires on '#' directives that lead a line (whitespace-only
    -- before '#'), never on trailing '# ...' asm comments. Removing this breaks
    -- the query (unknown predicate). Registered at startup, before any highlight.
    vim.treesitter.query.add_predicate("at-line-start?", function(match, _, source, predicate)
      local nodes = match[predicate[2]]
      if not nodes or #nodes == 0 then
        return true
      end
      for _, node in ipairs(nodes) do
        local srow, scol = node:range()
        if scol > 0 then
          if type(source) ~= "number" then
            return false
          end
          local line = vim.api.nvim_buf_get_lines(source, srow, srow + 1, false)[1] or ""
          if line:sub(1, scol):find("%S") then
            return false
          end
        end
      end
      return true
    end, { force = true })
  end,
}
