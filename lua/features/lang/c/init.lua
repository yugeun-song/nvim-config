-- C and C++ buffers: indentation from the project, else the C coding style's; gf on #include; <C-]> through tags.
-- The macro painter starts with the assembly painters (lua/plugins/lang/asm.lua), whose scanner it shares.
local M = {}

-- gf on #include serves these; the rest serve C and C++ only.
M.FILETYPES = { "c", "cpp", "objc", "objcpp", "cuda", "asm", "ld" }

function M.setup()
  local group = vim.api.nvim_create_augroup("c_and_cpp", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "c", "cpp" },
    callback = function(args)
      require("features.lang.c.indentation").apply(args.buf)
      require("features.lang.c.coding_style").apply(args.buf)
    end,
    desc = "Indent C/C++ per .clang-format, else tabs if the file uses them, else 4 spaces; C sources without one get 100 columns",
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = M.FILETYPES,
    callback = function(args)
      require("features.lang.c.include_gf").map(args.buf)
    end,
    desc = "gf on #include opens the header the project's compile database, tags or cscope place in the project",
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      local ft = vim.bo[args.buf].filetype

      if ft == "c" or ft == "cpp" or ft == "asm" then
        vim.bo[args.buf].tagfunc = ""
      end
    end,
    desc = "Clear LSP tagfunc on C/C++ and assembler buffers so <C-]> falls back to tags file",
  })
end

return M
