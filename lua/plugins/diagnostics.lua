return {
  "neovim/nvim-lspconfig",
  opts = {
    inlay_hints = { enabled = false },
  },
  config = function(_, opts)
    local lspconfig = require("lspconfig")

    for server, server_opts in pairs(opts.servers or {}) do
      local is_valid_lsp = pcall(require, "lspconfig.configs." .. server)
      if is_valid_lsp then
        server_opts.capabilities = require("blink.cmp").get_lsp_capabilities(server_opts.capabilities)
        lspconfig[server].setup(server_opts)
      end
    end

    vim.api.nvim_create_autocmd("CursorHold", {
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
            buffer = vim.api.nvim_get_current_buf(),
            callback = function()
              local current_line = vim.api.nvim_win_get_cursor(0)[1]
              if current_line ~= start_line then
                pcall(vim.api.nvim_win_close, winid, true)
                return true
              end
            end,
          })
        end
      end,
    })
  end,
}
