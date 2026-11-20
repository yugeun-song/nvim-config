-- C-family buffers: indentation from the project, else the C coding style's; gf on #include; <C-]> through tags.
-- The macro painter starts with the assembly painters (lua/plugins/lang/asm.lua), whose scanner it shares.
local M = {}

-- The C coding style (its indentation, clang-format's style, 100 columns) and <C-]> through tags serve these.
M.STYLED = { "c", "cpp", "cuda" }

-- clangd's languages: the styled ones and Objective-C, which keeps clang-format's defaults. lua/config/options.lua
-- and all_ifdef_branches/filetypes.lua read them.
M.C_FAMILY = vim.list_extend(vim.list_slice(M.STYLED), { "objc", "objcpp" })

-- gf on #include serves these.
M.FILETYPES = vim.list_extend(vim.list_slice(M.C_FAMILY), { "asm", "ld" })

function M.setup()
  local group = vim.api.nvim_create_augroup("c_and_cpp", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = M.STYLED,
    callback = function(args)
      require("features.lang.c.indentation").apply(args.buf)
      require("features.lang.c.coding_style").apply(args.buf)
    end,
    desc = "Indent C, C++ and CUDA per .clang-format, else tabs if the file uses them, else 4 spaces; 100 columns without one",
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

      if ft == "asm" or vim.list_contains(M.STYLED, ft) then
        vim.bo[args.buf].tagfunc = ""
      end
    end,
    desc = "Clear LSP tagfunc on C, C++, CUDA and assembler buffers so <C-]> falls back to tags file",
  })
end

return M
