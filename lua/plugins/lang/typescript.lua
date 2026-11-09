-- Parts adapted from https://github.com/LazyVim/LazyVim (Apache-2.0). See THIRD-PARTY-NOTICES.
-- JavaScript and TypeScript: vtsls and oxlint as language servers, js-debug for nvim-dap. oxfmt formats them
-- (lua/plugins/formatting.lua).
return {
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "js-debug-adapter", "oxlint", "vtsls" } },
  },
  {
    "mfussenegger/nvim-dap",
    optional = true,
    -- js-debug is a mason package with no plugin to load.
    opts = function()
      local dap = require("dap")
      local command = require("features.lsp.mason").bin("js-debug-adapter")

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
}
