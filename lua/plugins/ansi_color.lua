return {
  "m00qek/baleia.nvim",
  -- pinned to the audited commit; bump ONLY after `baleia-audit` passes
  commit = "710537ff5cd669c5a76c5f5b6a9169fd9b913d18",
  cmd = "BaleiaColorize",
  config = function()
    local baleia = require("baleia").setup({})
    vim.api.nvim_create_user_command("BaleiaColorize", function()
      baleia.once(vim.api.nvim_get_current_buf())
    end, { desc = "Interpret ANSI SGR escape codes in this buffer as colors" })
  end,
}
