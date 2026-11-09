-- Elixir: Expert as the language server, ElixirLS only for its debug adapter.
-- Expert's Erlang nodes listen on every interface with the public cookie "expert": anyone reaching a port runs code.
-- A per-session cookie closes that; ERL_FLAGS keeps the manager on loopback (Expert drops it for the engine).
local cookie = vim.uv.random(24):gsub(".", function(c)
  return ("%02x"):format(c:byte())
end)

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "elixir", "heex", "eex" } },
  },
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "elixir-ls", "expert" } },
  },
  {
    -- expert is the language server; elixir-ls stays installed only for its debug adapter.
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        elixirls = { enabled = false },
        expert = {
          cmd_env = {
            RELEASE_COOKIE = cookie,
            ERL_FLAGS = "-kernel inet_dist_use_interface {127,0,0,1}",
          },
        },
      },
    },
  },
  {
    "mfussenegger/nvim-dap",
    optional = true,
    -- ElixirLS ships the adapter (a mason package); nvim-dap drives it as a mix task.
    opts = function()
      local dap = require("dap")

      if not dap.adapters.mix_task then
        dap.adapters.mix_task = {
          type = "executable",
          command = require("features.lsp.mason").bin("elixir-ls-debugger"),
          args = {},
        }
      end

      if not dap.configurations.elixir then
        dap.configurations.elixir = {
          {
            type = "mix_task",
            name = "mix test",
            request = "launch",
            task = "test",
            taskArgs = { "--trace" },
            projectDir = "${workspaceFolder}",
            -- The debugger interprets the test files, so it must be told which.
            requireFiles = { "test/**/test_helper.exs", "test/**/*_test.exs" },
            startApps = true,
          },
          {
            type = "mix_task",
            name = "mix run",
            request = "launch",
            task = "run",
            projectDir = "${workspaceFolder}",
          },
        }
      end
    end,
  },
}
