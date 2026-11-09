-- nvim-dap and this configuration's debugger: when it loads (the keys below) and with what. The setup itself is
-- lua/features/dap/core/init.lua, loaded with nvim-dap.
return {
  {
    "mason-org/mason.nvim",
    -- The LLDB adapter of the macOS and Windows configurations, and rustaceanvim's.
    opts = { ensure_installed = { "codelldb" } },
  },
  {
    "mfussenegger/nvim-dap",
    -- Its commands load it too (lua/features/dap/core/init.lua defines them).
    cmd = {
      "DbgBreak",
      "DbgBreakpoints",
      "DbgClose",
      "DbgControlFlow",
      "DbgInline",
      "DbgLayout",
      "DbgLayoutReset",
      "DbgLog",
      "DbgMappings",
      "DbgMemory",
      "DbgRegisters",
      "DbgSafeMem",
      "DbgState",
      "DbgTargets",
    },
    dependencies = {
      {
        "igorlfs/nvim-dap-view",
        opts = function()
          return require("features.dap.core").dap_view_options()
        end,
      },
      {
        "https://codeberg.org/Jorenar/nvim-dap-disasm.git",
        opts = {
          dapui_register = false,
          dapview_register = true,
          dapview = { keymap = "D", label = "Dis(D)", short_label = "Dis(D)" },
          -- GDB's DAP mishandles a negative instructionOffset (the window never
          -- contains the reference), so start at the program counter.
          ins_before_memref = 0,
          ins_after_memref = 40,
          columns = { "address", "instructionBytes", "instruction" },
        },
      },
    },
    keys = {
      {
        "<leader>db",
        function()
          local dap = require("dap")

          if require("features.dap.core.sessions.session_profile").has_panels() then
            local ok, reason = require("features.dap.core.sessions.target_capabilities").supports("line_breakpoints")

            if not ok then
              require("features.dap.core.sessions.notifications").warn(reason .. " (<leader>dF)")

              return
            end
          end

          dap.toggle_breakpoint()
        end,
        desc = "Debug: toggle breakpoint",
      },
      {
        "<leader>dF",
        function()
          require("features.dap.core.sessions.function_and_address_breakpoints").prompt()
        end,
        desc = "Debug: break on a function name or address",
      },
      {
        "<leader>dg",
        function()
          require("features.dap.core.sessions.function_and_address_breakpoints").pick()
        end,
        desc = "Debug: list every breakpoint",
      },
      {
        "<leader>dB",
        function()
          vim.ui.input({ prompt = "Breakpoint condition: " }, function(cond)
            if cond then
              require("dap").set_breakpoint(cond)
            end
          end)
        end,
        desc = "Debug: conditional breakpoint",
      },
      {
        "<leader>dc",
        function()
          require("features.dap.core.sessions.target_session").cont()
        end,
        desc = "Debug: run / continue (replays the last configuration)",
      },
      {
        "<leader>dn",
        function()
          require("features.dap.core.sessions.target_session").pick()
        end,
        desc = "Debug: new session, choose the configuration again",
      },
      {
        "<leader>ds",
        function()
          require("features.dap.core.sessions.target_session").open()
        end,
        desc = "Debug: session / target info",
      },
      {
        "<leader>dC",
        function()
          local dap = require("dap")
          local session = dap.session()

          if not (session and require("features.dap.core.sessions.session_profile").is_gdb(session)) then
            dap.run_to_cursor()

            return
          end

          if not session.stopped_thread_id then
            require("features.dap.core.sessions.notifications").info("Run to cursor needs the target stopped")

            return
          end

          local where

          if vim.bo.buftype == "" then
            where = { source = vim.api.nvim_buf_get_name(0), line = vim.api.nvim_win_get_cursor(0)[1] }
          elseif vim.bo.filetype == "dap-disassembly" then
            local addr = vim.api.nvim_get_current_line():match("^%s*(0x%x+)")

            where = addr and { address = addr }
          end

          if not where then
            require("features.dap.core.sessions.notifications").warn(
              "Run to cursor needs a source line or a disassembly address"
            )

            return
          end

          require("features.dap.core.sessions.function_and_address_breakpoints").run_to(session, where)
        end,
        desc = "Debug: run to cursor",
      },
      {
        "<leader>di",
        function()
          require("features.dap.core.sessions.target_session").step("into")
        end,
        desc = "Debug: step into",
      },
      {
        "<leader>do",
        function()
          require("features.dap.core.sessions.target_session").step("over")
        end,
        desc = "Debug: step over (next)",
      },
      {
        "<leader>dO",
        function()
          require("features.dap.core.sessions.target_session").step("out")
        end,
        desc = "Debug: step out (finish)",
      },
      {
        "<leader>dj",
        function()
          require("dap").down()
        end,
        desc = "Debug: frame down",
      },
      {
        "<leader>dk",
        function()
          require("dap").up()
        end,
        desc = "Debug: frame up",
      },
      {
        "<leader>dl",
        function()
          require("dap").run_last()
        end,
        desc = "Debug: run last",
      },
      {
        "<leader>dP",
        function()
          require("dap").pause()
        end,
        desc = "Debug: pause",
      },
      {
        "<leader>dt",
        function()
          require("features.dap.core.sessions.target_session").stop()
        end,
        desc = "Debug: stop (detach when attached)",
      },
      {
        "<leader>dT",
        function()
          local dap = require("dap")
          local session = dap.session()

          if not session then
            dap.terminate()

            return
          end

          require("features.dap.core.sessions.all_stop_remote").halt(session, function()
            dap.terminate()
          end)
        end,
        desc = "Debug: terminate (kills the guest)",
      },
      {
        "<leader>dr",
        function()
          require("dap").repl.toggle()
        end,
        desc = "Debug: toggle the debug console",
      },
      {
        "<leader>du",
        function()
          require("dap-view").toggle()
        end,
        desc = "Debug: toggle panel",
      },
      {
        "<leader>de",
        function()
          require("dap-view").hover()
        end,
        mode = { "n", "x" },
        desc = "Debug: evaluate",
      },
      {
        "<leader>dw",
        function()
          -- A panel has no expression under the cursor; ask for one there.
          local in_panel = require("features.dap.core.panels.buffers_and_windows").is_debug_ft(vim.bo.filetype)
            or vim.bo.buftype ~= ""

          local word = vim.fn.expand("<cexpr>")

          if in_panel or vim.trim(word) == "" then
            vim.ui.input({ prompt = "Watch expression: ", default = vim.trim(word) }, function(answer)
              if answer and vim.trim(answer) ~= "" then
                require("dap-view").add_expr(vim.trim(answer))
              end
            end)

            return
          end

          require("dap-view").add_expr()
        end,
        mode = { "n", "x" },
        desc = "Debug: add watch",
      },
      {
        "<leader>dR",
        function()
          require("features.dap.core.panels.registers").open()
        end,
        desc = "Debug: registers",
      },
      {
        "<leader>dm",
        function()
          require("features.dap.core.panels.memory").open()
        end,
        desc = "Debug: memory view",
      },
      {
        "<leader>dD",
        function()
          if require("features.dap.core.sessions.session_profile").block_if_managed("The disassembly view") then
            return
          end

          vim.cmd("DapDisasm")
        end,
        desc = "Debug: disassembly",
      },
    },
    config = function()
      require("features.dap.core").setup()
    end,
  },
}
