-- Debug support for the languages that are not gdb targets: each one wired the
-- way its own ecosystem wires it. Nothing here goes through lua/dbg.

-- Mason puts its bin directory on PATH only once loaded, and nvim-dap can come
-- first, so prefer the path.
local function mason_bin(name)
  local path = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", name)
  if vim.uv.fs_stat(path) then
    return path
  end
  return name
end

return {
  ---------------------------------------------------------------- python
  {
    "mfussenegger/nvim-dap",
    optional = true,
    dependencies = {
      {
        "mfussenegger/nvim-dap-python",
        -- stylua: ignore
        keys = {
          { "<leader>dPt", function() require("dap-python").test_method() end, desc = "Debug: python test method", ft = "python" },
          { "<leader>dPc", function() require("dap-python").test_class() end, desc = "Debug: python test class", ft = "python" },
        },
        config = function()
          require("dap-python").setup(mason_bin("debugpy-adapter"))
        end,
      },
    },
  },

  ---------------------------------------------------------------- javascript / typescript
  {
    "mfussenegger/nvim-dap",
    optional = true,
    -- js-debug is a mason package with no plugin to load. lazy.nvim resolves opts
    -- before config, which is when nvim-dap wants the adapter.
    opts = function()
      local dap = require("dap")
      local command = mason_bin("js-debug-adapter")

      for _, kind in ipairs({ "node", "chrome", "msedge" }) do
        local pwa = "pwa-" .. kind
        if not dap.adapters[pwa] then
          dap.adapters[pwa] = {
            type = "server",
            host = "localhost",
            port = "${port}",
            executable = { command = command, args = { "${port}" } },
          }
        end
        -- A launch.json written for VS Code names the adapter without the prefix.
        if not dap.adapters[kind] then
          dap.adapters[kind] = function(cb, config)
            local native = dap.adapters[pwa]
            config.type = pwa
            if type(native) == "function" then
              native(cb, config)
            else
              cb(native)
            end
          end
        end
      end

      local filetypes = { "javascript", "typescript", "javascriptreact", "typescriptreact" }
      local vscode = require("dap.ext.vscode")
      vscode.type_to_filetypes["node"] = filetypes
      vscode.type_to_filetypes["pwa-node"] = filetypes

      for _, ft in ipairs(filetypes) do
        if not dap.configurations[ft] then
          -- A .ts file needs a TypeScript-capable runner; .js runs on node itself.
          local runtimeExecutable = nil
          if ft:find("typescript") then
            runtimeExecutable = vim.fn.executable("tsx") == 1 and "tsx" or "ts-node"
          end
          dap.configurations[ft] = {
            {
              type = "pwa-node",
              request = "launch",
              name = "Launch file",
              program = "${file}",
              cwd = "${workspaceFolder}",
              sourceMaps = true,
              runtimeExecutable = runtimeExecutable,
              skipFiles = { "<node_internals>/**", "node_modules/**" },
              resolveSourceMapLocations = { "${workspaceFolder}/**", "!**/node_modules/**" },
            },
            {
              type = "pwa-node",
              request = "attach",
              name = "Attach",
              processId = require("dap.utils").pick_process,
              cwd = "${workspaceFolder}",
              sourceMaps = true,
              runtimeExecutable = runtimeExecutable,
              skipFiles = { "<node_internals>/**", "node_modules/**" },
              resolveSourceMapLocations = { "${workspaceFolder}/**", "!**/node_modules/**" },
            },
          }
        end
      end
    end,
  },

  ---------------------------------------------------------------- elixir
  {
    "mfussenegger/nvim-dap",
    optional = true,
    -- ElixirLS ships the debug adapter; nvim-dap drives it as a mix task, which is
    -- how the Elixir side documents it. No plugin to load: it is a mason package.
    opts = function()
      local dap = require("dap")
      if not dap.adapters.mix_task then
        dap.adapters.mix_task = {
          type = "executable",
          command = mason_bin("elixir-ls-debugger"),
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
            -- The debugger interprets the test files, so it has to be told which
            -- ones; a task that is not `test` needs none of this.
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

  ---------------------------------------------------------------- rust
  {
    "mrcjkb/rustaceanvim",
    ft = { "rust" },
    -- stylua: ignore
    keys = {
      { "<leader>dPr", function() vim.cmd.RustLsp("debuggables") end, desc = "Debug: rust debuggables", ft = "rust" },
    },
    config = function()
      -- rustaceanvim finds the cargo targets itself; it only needs the adapter.
      local opts = {}
      local codelldb = mason_bin("codelldb")
      if vim.uv.fs_stat(codelldb) then
        local lib = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "opt", "lldb", "lib", "liblldb.so")
        opts.dap = {
          adapter = require("rustaceanvim.config").get_codelldb_adapter(codelldb, vim.uv.fs_stat(lib) and lib or nil),
        }
      end
      vim.g.rustaceanvim = vim.tbl_deep_extend("keep", vim.g.rustaceanvim or {}, opts)
    end,
  },
  {
    -- rustaceanvim runs its own rust-analyzer; lspconfig's would be a second one.
    "neovim/nvim-lspconfig",
    opts = { servers = { rust_analyzer = { enabled = false } } },
  },
}
