-- Parts adapted from https://github.com/LazyVim/LazyVim (Apache-2.0). See THIRD-PARTY-NOTICES.
-- Debug support for languages that are not gdb targets; nothing here goes through lua/dbg.

local MASON = vim.fs.joinpath(vim.fn.stdpath("data"), "mason")

-- Mason extends PATH only once loaded, and nvim-dap can come first. uv.spawn
-- finds Mason's Windows .cmd shims only by full name, which exepath gives.
local function mason_bin(name)
  local path = vim.fn.exepath(vim.fs.joinpath(MASON, "bin", name))
  return path ~= "" and path or name
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
          local venv = vim.fs.joinpath(MASON, "packages", "debugpy", "venv")
          local python =
            vim.fn.exepath(vim.fs.joinpath(venv, vim.fn.has("win32") == 1 and "Scripts" or "bin", "python"))
          require("dap-python").setup(python ~= "" and python or nil)
        end,
      },
    },
  },

  ---------------------------------------------------------------- javascript / typescript
  {
    "mfussenegger/nvim-dap",
    optional = true,
    -- js-debug is a mason package with no plugin to load.
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
          -- node strips TypeScript types itself; enums and namespaces need tsx or ts-node.
          local runtimeExecutable = nil
          if ft:find("typescript") then
            for _, runner in ipairs({ "tsx", "ts-node" }) do
              if vim.fn.executable(runner) == 1 then
                runtimeExecutable = runner
                break
              end
            end
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
    -- ElixirLS ships the adapter (a mason package); nvim-dap drives it as a mix task.
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

  ---------------------------------------------------------------- rust
  {
    "mrcjkb/rustaceanvim",
    ft = { "rust" },
    -- stylua: ignore
    keys = {
      { "<leader>dPr", function() vim.cmd.RustLsp("debuggables") end, desc = "Debug: rust debuggables", ft = "rust" },
    },
    config = function()
      -- rustaceanvim finds the cargo targets and Mason's codelldb itself.
      local opts = {
        server = {
          settings = function(project_root, default_settings)
            local settings = require("rustaceanvim.config.server").load_rust_analyzer_settings(project_root, {
              default_settings = default_settings,
            })
            local detached = not project_root
              or not vim.fs.find({ "Cargo.toml", "rust-project.json" }, { path = project_root, upward = true })[1]
            if detached then
              local ra = settings["rust-analyzer"]
              ra.cargo = vim.tbl_deep_extend("force", ra.cargo or {}, {
                extraEnv = { RUSTC_BOOTSTRAP = "1" },
                autoreload = false,
              })
            end
            return settings
          end,
        },
      }
      vim.g.rustaceanvim = vim.tbl_deep_extend("keep", vim.g.rustaceanvim or {}, opts)
    end,
  },
  {
    -- rustaceanvim runs its own rust-analyzer; lspconfig's would be a second one.
    "neovim/nvim-lspconfig",
    opts = { servers = { rust_analyzer = { enabled = false } } },
  },
}
