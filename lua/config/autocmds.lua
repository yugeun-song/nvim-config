-- Parts adapted from https://github.com/LazyVim/LazyVim (Apache-2.0). See THIRD-PARTY-NOTICES.
local function augroup(name)
  return vim.api.nvim_create_augroup("lazyvim_" .. name, { clear = true })
end

vim.api.nvim_create_autocmd("FileType", {
  group = augroup("wrap_spell"),
  pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
  callback = function()
    vim.opt_local.wrap = true
  end,
  desc = "Replace LazyVim's wrap_spell: wrap prose buffers but leave spell off",
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = augroup("claude_prompt"),
  pattern = "claude-prompt-*.md",
  callback = function(args)
    vim.schedule(function()
      vim.lsp.buf_detach_client(args.buf, args.data.client_id)
    end)
  end,
  desc = "Keep LSP clients off the prompt file Claude Code opens on Ctrl+G",
})
