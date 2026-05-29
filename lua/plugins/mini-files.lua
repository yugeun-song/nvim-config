return {
  "nvim-mini/mini.files",
  opts = function(_, opts)
    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("MiniFilesEnterOpen", { clear = true }),
      pattern = "MiniFilesBufferCreate",
      callback = function(args)
        vim.keymap.set("n", "<CR>", function()
          require("mini.files").go_in({ close_on_file = true })
        end, { buffer = args.data.buf_id, desc = "Open entry (file/dir)" })
      end,
    })
    return opts
  end,
}
