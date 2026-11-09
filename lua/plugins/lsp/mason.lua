-- Mason packages no language file of lua/plugins/lang/ asks for. Each language file, formatting.lua, linting.lua
-- and dap/core.lua add their own; LazyVim joins the lists.
local specs = {
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        "awk-language-server",
        "bash-language-server",
        "css-lsp",
        "docker-language-server",
        "elp",
        "html-lsp",
        "jdtls",
        "json-lsp",
        "julia-lsp",
        "kotlin-lsp",
        "lua-language-server",
        "shellcheck",
        "wasm-language-tools",
        "yaml-language-server",
      },
    },
  },
}

-- Windows: Mason installs no package whose runtime is missing (Java, Elixir, Erlang, Julia), nor one whose install
-- failed lately (lua/features/lsp/mason/windows_install_gate.lua); what is installed stays. It filters the list
-- every other spec has added to, so lua/config/lazy.lua imports this directory last.
if vim.fn.has("win32") == 1 then
  specs[#specs + 1] = {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      local held = require("features.lsp.mason.windows_install_gate")

      opts.ensure_installed = held.filter(opts.ensure_installed or {})
      held.track()
    end,
  }
end

return specs
