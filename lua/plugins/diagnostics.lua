local function setup()
  local group = vim.api.nvim_create_augroup("UserLspDiagnostics", { clear = true })
  local close_id

  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = function()
      if not vim.diagnostic.is_enabled({ bufnr = vim.api.nvim_get_current_buf() }) then
        return
      end

      local ok, _, winid = pcall(vim.diagnostic.open_float, nil, {
        focusable = false,
        close_events = { "CursorMovedI", "BufHidden", "InsertCharPre" },
        border = "rounded",
        source = "always",
        prefix = " ",
        scope = "line",
      })

      if not (ok and winid) then
        return
      end

      if close_id then
        pcall(vim.api.nvim_del_autocmd, close_id)
      end

      local start_line = vim.api.nvim_win_get_cursor(0)[1]

      close_id = vim.api.nvim_create_autocmd("CursorMoved", {
        group = group,
        buffer = 0,
        callback = function()
          if vim.api.nvim_win_get_cursor(0)[1] ~= start_line then
            if vim.api.nvim_win_is_valid(winid) then
              pcall(vim.api.nvim_win_close, winid, true)
            end

            close_id = nil

            return true
          end
        end,
      })
    end,
    desc = "Show line diagnostics automatically on CursorHold",
  })
end

return {
  {
    "diagnostic_float",
    virtual = true,
    event = "VeryLazy",
    config = setup,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      inlay_hints = { enabled = false },
    },
  },
}
