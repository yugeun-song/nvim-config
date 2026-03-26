local diag_augroup = vim.api.nvim_create_augroup("UserLspDiagnostics", { clear = true })

vim.api.nvim_create_autocmd("CursorHold", {
  group = diag_augroup,
  callback = function()
    local ok, _, winid = pcall(vim.diagnostic.open_float, nil, {
      focusable = false,
      close_events = { "CursorMovedI", "BufHidden", "InsertCharPre" },
      border = "rounded",
      source = "always",
      prefix = " ",
      scope = "line",
    })

    if ok and winid then
      local start_line = vim.api.nvim_win_get_cursor(0)[1]

      vim.api.nvim_create_autocmd("CursorMoved", {
        group = diag_augroup,
        buffer = 0,
        callback = function()
          local current_line = vim.api.nvim_win_get_cursor(0)[1]
          if current_line ~= start_line then
            if vim.api.nvim_win_is_valid(winid) then
              pcall(vim.api.nvim_win_close, winid, true)
            end
            return true
          end
        end,
      })
    end
  end,
  desc = "Show line diagnostics automatically on CursorHold",
})

return {
  "neovim/nvim-lspconfig",
  opts = {
    inlay_hints = { enabled = false },
  },
}
