-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>uk", function()
  local current = vim.g.kernel_diag_mute_enabled
  if current == nil then
    current = true
  end
  local new_state = not current
  vim.g.kernel_diag_mute_enabled = new_state

  local changed = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      if ft == "c" or ft == "cpp" or ft == "h" then
        local bufname = vim.api.nvim_buf_get_name(buf)
        if bufname ~= "" then
          local dir = vim.fn.fnamemodify(bufname, ":h")
          if vim.fn.findfile(".nvim-diag-off", dir .. ";") ~= "" then
            vim.diagnostic.enable(not new_state, { bufnr = buf })
            changed = changed + 1
          end
        end
      end
    end
  end

  if new_state then
    pcall(vim.cmd, "silent! Trouble diagnostics close")
    pcall(vim.cmd, "silent! cclose")
    pcall(vim.cmd, "silent! lclose")
  end

  vim.notify(
    string.format(
      "Kernel diag mute: %s (%d buffer%s)",
      new_state and "ON (quiet)" or "OFF (showing)",
      changed,
      changed == 1 and "" or "s"
    )
  )
end, { desc = "Toggle diagnostic mute for .nvim-diag-off projects" })
