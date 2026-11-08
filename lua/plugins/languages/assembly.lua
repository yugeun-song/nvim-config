return {
  "nvim-treesitter/nvim-treesitter",
  -- c: a .S file's #-directives are read as C (after/queries/asm/injections.scm). c and cpp: the inline assembly
  -- of C, C++ and CUDA is painted from their trees (lua/features/languages/assembly/syntax_highlighting.lua).
  opts = { ensure_installed = { "asm", "c", "cpp", "linkerscript", "devicetree" } },
  init = function()
    -- #at-line-start? for after/queries/asm/injections.scm, which fails to load without it: the cpp injection
    -- fires only on a '#' that leads its line, never on a trailing asm comment.
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

    -- The painters run on every redraw of every window and gd in assembler needs its module: none of it is set up
    -- before the first buffer it serves.
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "asm", "c", "cpp", "cuda", "objc", "objcpp" },
      once = true,
      callback = function()
        require("features.languages.assembly.definition_navigation").setup()
        require("features.languages.assembly.syntax_highlighting").setup()
        require("features.languages.c_and_cpp.macro_body_highlighting").setup()
      end,
      desc = "Set up assembly navigation and the assembly and macro painters with the first buffer they serve",
    })
  end,
}
