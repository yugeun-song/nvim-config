local last_answer = {}

-- Keep asking until the answer is runnable: a typo used to be accepted, remembered,
-- and then replayed by every later <leader>dc.
local function input_path(prompt, default)
  return function()
    local seed = last_answer[prompt] or default()
    while true do
      local answer = vim.fn.input(prompt, seed, "file")
      if vim.trim(answer) == "" then
        return nil
      end
      answer = vim.fn.expand(answer)
      if vim.fn.filereadable(answer) == 1 and vim.fn.executable(answer) == 1 then
        last_answer[prompt] = answer
        return answer
      end
      local why = vim.fn.isdirectory(answer) == 1 and "is a directory"
        or vim.fn.filereadable(answer) == 0 and "no such file"
        or "not executable"
      vim.api.nvim_echo({ { ("%s %s"):format(answer, why), "WarningMsg" } }, false, {})
      seed = answer
    end
  end
end

local function split_args(line)
  local out, cur, started = {}, {}, false
  local i, n = 1, #line
  while i <= n do
    local c = line:sub(i, i)
    if c == " " or c == "\t" then
      if started then
        out[#out + 1] = table.concat(cur)
        cur, started = {}, false
      end
    elseif c == "'" then
      started = true
      local close = line:find("'", i + 1, true) or (n + 1)
      cur[#cur + 1] = line:sub(i + 1, close - 1)
      i = close
    elseif c == '"' then
      started = true
      i = i + 1
      while i <= n and line:sub(i, i) ~= '"' do
        if line:sub(i, i) == "\\" and i < n then
          i = i + 1
        end
        cur[#cur + 1] = line:sub(i, i)
        i = i + 1
      end
    elseif c == "\\" and i < n then
      started = true
      i = i + 1
      cur[#cur + 1] = line:sub(i, i)
    else
      started = true
      cur[#cur + 1] = c
    end
    i = i + 1
  end
  if started then
    out[#out + 1] = table.concat(cur)
  end
  return out
end

local function input_args(prompt)
  return function()
    local line = vim.fn.input(prompt, last_answer[prompt] or "", "file")
    last_answer[prompt] = line
    local list = split_args(line)
    if #list == 0 then
      return nil
    end
    return list
  end
end

local function cwd_exe()
  return vim.fn.getcwd() .. "/"
end

local function cargo_target()
  local root = vim.fs.root(0, { "Cargo.toml" }) or vim.fn.getcwd()
  local manifest = root .. "/Cargo.toml"
  local name
  local fd = io.open(manifest, "r")
  if fd then
    local inside = false
    for line in fd:lines() do
      if line:match("^%s*%[package%]") then
        inside = true
      elseif line:match("^%s*%[") then
        inside = false
      elseif inside then
        name = name or line:match('^%s*name%s*=%s*"([^"]+)"')
      end
    end
    fd:close()
  end
  local guess = name and (root .. "/target/debug/" .. name) or (root .. "/target/debug/")
  return guess
end

local function rust_init_commands()
  local sysroot = vim.fn.system({ "rustc", "--print", "sysroot" })
  if vim.v.shell_error ~= 0 then
    return {}
  end
  local etc = vim.trim(sysroot) .. "/lib/rustlib/etc"
  if vim.fn.filereadable(etc .. "/lldb_lookup.py") ~= 1 then
    return {}
  end
  return {
    "command script import " .. etc .. "/lldb_lookup.py",
    "command source -s 0 " .. etc .. "/lldb_commands",
  }
end

local function adaptive(full, short)
  return function(width)
    return (width or 0) >= 140 and full or short
  end
end

return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      {
        "igorlfs/nvim-dap-view",
        opts = {
          winbar = {
            show = true,
            show_keymap_hints = false,
            sections = {
              "scopes",
              "watch",
              "watches",
              "registers",
              "memory",
              "mappings",
              "controlflow",
              "disassembly",
              "threads",
              "breakpoints",
              "session",
              "repl",
              "console",
            },
            default_section = "scopes",
            base_sections = {
              scopes = { label = adaptive("Scopes(S)", "Sco(S)"), keymap = "S" },
              watches = { label = adaptive("Watches(W)", "Wat(W)"), keymap = "W" },
              threads = { label = adaptive("Call stack(T)", "Stk(T)"), keymap = "T" },
              breakpoints = { label = adaptive("Breakpoints(B)", "Brk(B)"), keymap = "B" },
              repl = { label = adaptive("gdb console(R)", "gdb(R)"), keymap = "R" },
              console = { label = adaptive("Output(C)", "Out(C)"), keymap = "C" },
              exceptions = { label = adaptive("Exceptions(E)", "Exc(E)"), keymap = "E" },
              sessions = { label = adaptive("Sessions(K)", "Ses(K)"), keymap = "K" },
            },
            custom_sections = {
              watch = {
                label = adaptive("Locals+Globals(A)", "Var(A)"),
                keymap = "A",
                action = function()
                  require("dbg.watch").probe()
                end,
                buffer = function()
                  return require("dbg.watch").buffer()
                end,
              },
              registers = {
                label = adaptive("Registers(G)", "Reg(G)"),
                keymap = "G",
                action = function()
                  require("dbg.registers").render()
                end,
                buffer = function()
                  return require("dbg.registers").buffer()
                end,
              },
              memory = {
                label = adaptive("Memory(M)", "Mem(M)"),
                keymap = "M",
                action = function()
                  require("dbg.memory").refresh()
                end,
                buffer = function()
                  return require("dbg.memory").buffer()
                end,
              },
              mappings = {
                label = adaptive("Mappings(V)", "Map(V)"),
                keymap = "V",
                action = function()
                  require("dbg.mappings").probe()
                end,
                buffer = function()
                  return require("dbg.mappings").buffer()
                end,
              },
              controlflow = {
                label = adaptive("Control flow(F)", "CFG(F)"),
                keymap = "F",
                action = function()
                  require("dbg.cfg").probe()
                end,
                buffer = function()
                  return require("dbg.cfg").buffer()
                end,
              },
              session = {
                label = adaptive("Target(I)", "Tgt(I)"),
                keymap = "I",
                action = function()
                  require("dbg.session").probe()
                end,
                buffer = function()
                  return require("dbg.session").buffer()
                end,
              },
            },
          },
          windows = {
            size = 0.34,
            position = "below",
            terminal = { position = "left", hide = { "gdb", "gdb_kernel" } },
          },
          virtual_text = { enabled = true },
          auto_toggle = true,
        },
      },
      {
        "https://codeberg.org/Jorenar/nvim-dap-disasm.git",
        opts = {
          dapui_register = false,
          dapview_register = true,
          dapview = { keymap = "D", label = "Dis(D)", short_label = "Dis(D)" },
          -- GDB's DAP mishandles a negative instructionOffset: the window it returns
          -- starts past the reference and never contains it, so the current instruction
          -- can never be marked. Start at the program counter instead.
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
          if dap.session() then
            local ok, reason = require("dbg.caps").supports("line_breakpoints")
            if not ok then
              require("dbg.notify").warn(reason .. " (<leader>dF)")
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
          require("dbg.breakpoints").prompt()
        end,
        desc = "Debug: break on a function name or address",
      },
      {
        "<leader>dg",
        function()
          require("dbg.breakpoints").pick()
        end,
        desc = "Debug: list every breakpoint",
      },
      {
        "<leader>dB",
        function()
          require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
        end,
        desc = "Debug: conditional breakpoint",
      },
      {
        "<leader>dc",
        function()
          require("dbg.session").cont()
        end,
        desc = "Debug: run / continue (replays the last configuration)",
      },
      {
        "<leader>dn",
        function()
          require("dbg.session").pick()
        end,
        desc = "Debug: new session, choose the configuration again",
      },
      {
        "<leader>ds",
        function()
          require("dbg.session").open()
        end,
        desc = "Debug: session / target info",
      },
      {
        "<leader>dC",
        function()
          require("dap").run_to_cursor()
        end,
        desc = "Debug: run to cursor",
      },
      {
        "<leader>di",
        function()
          require("dbg.session").step("into")
        end,
        desc = "Debug: step into",
      },
      {
        "<leader>do",
        function()
          require("dbg.session").step("over")
        end,
        desc = "Debug: step over (next)",
      },
      {
        "<leader>dO",
        function()
          require("dbg.session").step("out")
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
          require("dbg.session").stop()
        end,
        desc = "Debug: stop (detach when attached)",
      },
      {
        "<leader>dT",
        function()
          require("dap").terminate()
        end,
        desc = "Debug: terminate (kills the guest)",
      },
      {
        "<leader>dr",
        function()
          require("dap").repl.toggle()
        end,
        desc = "Debug: toggle gdb console",
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
          -- dap-view takes the expression under the cursor, and a panel has none, so
          -- ask for it there instead of adding nothing.
          local ft = vim.bo.filetype
          local in_panel = ft:match("^dbg%-") or ft:match("^dap%-") or vim.bo.buftype ~= ""
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
          require("dbg.registers").open()
        end,
        desc = "Debug: registers",
      },
      {
        "<leader>dm",
        function()
          require("dbg.memory").open()
        end,
        desc = "Debug: memory view",
      },
      { "<leader>dD", "<cmd>DapDisasm<cr>", desc = "Debug: disassembly" },
      {
        "<leader>dq",
        function()
          require("dbg.kernel").start()
        end,
        desc = "Debug: attach QEMU kernel",
      },
      {
        "<leader>dQ",
        function()
          require("dbg.kernel").show_report()
        end,
        desc = "Debug: QEMU targets report",
      },
    },
    config = function()
      local dap = require("dap")
      local discover = require("dbg.discover")

      -- bufferline's keys act on the current window, and the debugger's panels are
      -- winfixbuf, so pressing one with the cursor in a panel raises E1513.  Wrap
      -- the commands rather than rebinding whatever keys are configured.
      pcall(function()
        local commands = require("bufferline.commands")
        for _, name in ipairs({ "go_to", "cycle", "pick", "move", "exec" }) do
          local original = commands[name]
          if type(original) == "function" and not commands["dbg_wrapped_" .. name] then
            commands["dbg_wrapped_" .. name] = true
            commands[name] = function(...)
              require("dbg.layout").unfix_for_buffer_switch()
              return original(...)
            end
          end
        end
      end)

      dap.defaults.fallback.switchbuf = function(bufnr, line, column)
        require("dbg.layout").jump(bufnr, line, column)
      end

      -- nvim-dap says "Source missing, cannot jump to frame" on every stop in code with
      -- no line table, which is most of a kernel's early boot: arm64 puts primary_entry
      -- and __primary_switch in .rodata.text, uncovered by this build's DWARF line
      -- table. The session already says so once and shows the disassembly instead.
      local dap_utils = require("dap.utils")
      if not dap_utils.dbg_quiet_source_missing then
        local report = dap_utils.notify
        dap_utils.notify = function(msg, ...)
          if type(msg) == "string" and msg:find("^Source missing, cannot jump to frame") then
            return
          end
          return report(msg, ...)
        end
        dap_utils.dbg_quiet_source_missing = true
      end

      -- The userspace adapter loads the same toolkit as the kernel one: the
      -- control-flow panel's backend is architecture-generic and answers for an
      -- ordinary binary exactly as it does for a kernel.  The kernel-only
      -- commands register alongside it and stay inert without a vmlinux.
      dap.adapters.gdb = function(callback, config)
        local args = { "-q", "-i", "dap", "-iex", "set pagination off" }
        local tool = discover.gdbtools_loader(config and config.program and vim.fs.dirname(config.program))
        if tool then
          table.insert(args, "-ex")
          table.insert(args, "source " .. tool)
        end
        callback({ type = "executable", command = "gdb", args = args })
      end

      dap.adapters.gdb_kernel = function(callback, config)
        local bin = config.gdb_bin or discover.gdb_for(config.arch or "x86_64")
        local args = { "-q", "-i", "dap", "-iex", "set pagination off" }
        if config.kernel_root then
          table.insert(args, "-iex")
          table.insert(args, "add-auto-load-safe-path " .. config.kernel_root)
        end
        local tool = discover.gdbtools_loader(config.kernel_root)
        if tool then
          table.insert(args, "-ex")
          table.insert(args, "source " .. tool)
        end
        local env = vim.fn.environ()
        if config.kernel_root then
          env.GDBTOOLS_KERNEL_ROOT = config.kernel_root
        end
        if config.kgdb_auto then
          env.GDBTOOLS_AUTO = "1"
        end
        -- The extension carries no machine constants: it debugs whatever it is
        -- pointed at.  The tree describes its own machine in qemu.conf, so read it
        -- from there rather than restating it here, where it would drift from what
        -- the shell launcher reads.  Anything already in the environment wins.
        for k, v in pairs(discover.machine_facts(config.kernel_root)) do
          if not env[k] or env[k] == "" then
            env[k] = v
          end
        end
        -- x86 KASLR recovery reads the compressed image; where it sits relative to
        -- the build tree is our fact to supply, not something for it to guess.
        if config.kernel_root and (config.arch == "x86_64" or config.arch == "i386") then
          local decomp = config.kernel_root .. "/arch/x86/boot/compressed/vmlinux"
          if vim.uv.fs_stat(decomp) and not env.GDBTOOLS_X86_DECOMP_VMLINUX then
            env.GDBTOOLS_X86_DECOMP_VMLINUX = decomp
          end
        end
        -- x86 needs this in the process environment, not as a command: the
        -- decompressor-randomized base is recovered while the session starts.
        if config.kaslr_auto and (config.arch == "x86_64" or config.arch == "i386") then
          env.GDBTOOLS_X86_KASLR = "1"
        end
        local env_list = {}
        for k, v in pairs(env) do
          if k:find("^[^=]*$") then
            env_list[#env_list + 1] = k .. "=" .. tostring(v)
          end
        end
        callback({
          type = "executable",
          command = bin,
          args = args,
          options = { env = env_list },
        })
      end

      dap.adapters.lldb = {
        type = "executable",
        command = "lldb-dap",
      }

      local c_configs = {
        {
          name = "Launch executable (gdb)",
          type = "gdb",
          request = "launch",
          program = input_path("Executable: ", cwd_exe),
          args = input_args("Arguments: "),
          cwd = "${workspaceFolder}",
          stopAtBeginningOfMainSubprogram = false,
        },
        {
          name = "Launch executable, stop at main (gdb)",
          type = "gdb",
          request = "launch",
          program = input_path("Executable: ", cwd_exe),
          args = input_args("Arguments: "),
          cwd = "${workspaceFolder}",
          stopAtBeginningOfMainSubprogram = true,
        },
        {
          name = "Attach to a running process (gdb)",
          type = "gdb",
          request = "attach",
          program = input_path("Executable: ", cwd_exe),
          pid = function()
            return tonumber(vim.fn.input("PID: "))
          end,
        },
      }

      dap.configurations.c = c_configs
      dap.configurations.cpp = c_configs
      dap.configurations.asm = c_configs

      require("dbg.languages").setup(dap, {
        program = input_path,
        args = input_args,
        cargo_target = cargo_target,
        rust_init_commands = rust_init_commands,
      })

      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError", numhl = "" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticWarn", numhl = "" })
      vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DiagnosticHint", numhl = "" })
      vim.fn.sign_define("DapLogPoint", { text = "◇", texthl = "DiagnosticInfo", numhl = "" })
      vim.fn.sign_define(
        "DapStopped",
        { text = "▶", texthl = "DbgStopSign", linehl = "DbgStopLine", numhl = "DbgStopSign" }
      )

      -- Labelled "gdb console", so it behaves like one: <CR> sends the line under the
      -- cursor to GDB instead of nvim-dap's variable expansion, re-running old commands.
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "dap-repl",
        callback = function(ev)
          local buf = ev.buf
          -- blink.cmp makes an explicit exception for dap-repl and completes from buffer
          -- words there; a command line wants no popup. GDB's own completion is still
          -- one <C-x><C-o> away, through nvim-dap's omnifunc.
          vim.b[buf].completion = false
          local function prompt()
            return vim.fn.prompt_getprompt(buf)
          end
          local function to_prompt()
            local win = vim.fn.bufwinid(buf)
            if win == -1 then
              return
            end
            local last = vim.api.nvim_buf_line_count(buf)
            local text = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1] or ""
            pcall(vim.api.nvim_win_set_cursor, win, { last, #text })
          end
          vim.keymap.set("n", "<CR>", function()
            local pre = prompt()
            local lnum = vim.api.nvim_win_get_cursor(0)[1]
            local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
            if pre == "" or line:sub(1, #pre) ~= pre then
              require("dap.ui").trigger_actions({ mode = "first" })
              return
            end
            local command = line:sub(#pre + 1)
            local last = vim.api.nvim_buf_line_count(buf)
            if lnum ~= last then
              vim.bo[buf].modifiable = true
              pcall(vim.api.nvim_buf_set_lines, buf, last - 1, last, false, { pre .. command })
            end
            to_prompt()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("A<CR>", true, false, true), "n", false)
          end, { buffer = buf, desc = "gdb console: run this line in gdb" })
          for _, key in ipairs({ "i", "I", "a", "A" }) do
            vim.keymap.set("n", key, function()
              to_prompt()
              vim.cmd("startinsert!")
            end, { buffer = buf, desc = "gdb console: type at the prompt" })
          end
        end,
        desc = "Make the gdb console take commands the way a console does",
      })

      local ok_baleia, baleia = pcall(require, "baleia")
      if ok_baleia then
        local colorizer = baleia.setup({})
        vim.api.nvim_create_autocmd("FileType", {
          pattern = { "dap-repl", "dap-view-term" },
          callback = function(ev)
            pcall(colorizer.automatically, ev.buf)
          end,
          desc = "Colorize ANSI output from gdb / pwndbg in the debug console",
        })
      end

      require("dbg.ui").setup_highlights()
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          require("dbg.ui").setup_highlights()
        end,
        desc = "Keep the debugger panel highlights defined across colorscheme changes",
      })

      -- nvim-dap settles on a frame only once the stackTrace response lands, so paint
      -- from that response and not from the stopped event: reading `current_frame` any
      -- earlier gets the previous stop's.
      local awaiting = {}

      local function paint(session)
        if dap.session() ~= session then
          return
        end
        pcall(function()
          require("dbg.registers").render()
          require("dbg.watch").probe()
          require("dbg.memory").on_stopped()
          require("dbg.session").probe()
          require("dbg.mappings").probe()
          require("dbg.cfg").probe()
          require("dbg.layout").resize()
          if not require("dbg.console").has_source(session.current_frame) then
            pcall(vim.fn.sign_unplace, session.sign_group)
            require("dbg.layout").show_disassembly()
          end
        end)
        -- nvim-dap-disasm only redraws when its buffer is on screen and keys off the
        -- scopes response; ask it directly once the window is settled.
        vim.schedule(function()
          pcall(function()
            require("dap-disasm").refresh()
          end)
          vim.defer_fn(function()
            pcall(function()
              require("dbg.disasm").mark(session)
            end)
          end, 250)
        end)
      end

      dap.listeners.after.event_stopped["dbg_panels"] = function(session, body)
        pcall(function()
          require("dbg.registers").mark_stop()
        end)
        -- Remember which thread reported the stop: with several halted vCPUs the client
        -- would otherwise ask, and moving the wrong one resumes the whole machine.
        if body and body.threadId then
          session.dbg_stopped_thread = body.threadId
        end
        awaiting[session.id] = true
      end

      dap.listeners.after.stackTrace["dbg_panels"] = function(session, err, _, payload)
        if not awaiting[session.id] then
          return
        end
        if payload and payload.startFrame and payload.startFrame > 0 then
          return
        end
        awaiting[session.id] = nil
        if not err then
          -- Put the selection back on frame 0 before anything reads it,
          -- otherwise the registers and the scopes describe the caller.
          pcall(function()
            require("dbg.console").realign(session)
          end)
        end
        vim.schedule(function()
          paint(session)
        end)
      end

      local function snapshot_layout()
        pcall(function()
          require("dbg.layout").snapshot()
        end)
      end

      dap.listeners.after.initialize["dbg_panels"] = snapshot_layout
      dap.listeners.before.event_initialized["dbg_panels"] = snapshot_layout

      dap.listeners.after.event_initialized["dbg_panels"] = function(session)
        pcall(function()
          require("dbg.caps").invalidate(session)
          require("dbg.session").remember(session.config)
          require("dbg.layout").enter()
          require("dbg.kernel").arm_kaslr(session)
          require("dbg.kernel").watch_target(session)
        end)
      end

      local function teardown(session)
        pcall(function()
          require("dbg.caps").invalidate(session)
          require("dbg.kernel").stop_watchdog()
        end)
        vim.schedule(function()
          if require("dap").session() then
            return
          end
          pcall(function()
            require("dbg.layout").leave()
          end)
        end)
      end

      -- Losing the QEMU gdbstub does not terminate the DAP session, so nothing
      -- would otherwise say the panels have gone stale.
      -- A binary with no DWARF is a normal thing to attach to; it is only worth
      -- saying once, at the start, so the panels are read for what they can
      -- actually show.  Nothing is rebuilt and nothing is disabled beyond what
      -- the missing information already makes impossible.
      dap.listeners.after.event_initialized["dbg_debuginfo"] = function(session)
        pcall(function()
          local prog = (session.config or {}).program
          local kind = prog and require("dbg.discover").elf_debug_info(prog)
          if kind ~= "none" and kind ~= "stripped" then
            return
          end
          session.dbg_no_debug_info = true
          local why = kind == "stripped"
              and "is stripped, so unless debuginfod or a debug package supplies it there are no source lines, locals or types"
            or "was built without -g, so there are no source lines, locals or types"
          require("dbg.notify").warn(
            ("%s %s. "):format(vim.fs.basename(prog), why)
              .. "Disassembly, registers, memory, breakpoints and the control-flow graph still work."
          )
        end)
      end

      dap.listeners.after.event_initialized["dbg_watchdog"] = function(session)
        pcall(function()
          require("dbg.watchdog").start(session)
        end)
      end
      dap.listeners.after.event_output["dbg_watchdog"] = function(_, body)
        pcall(function()
          require("dbg.watchdog").saw_text(body and body.output)
        end)
      end
      dap.listeners.after.event_terminated["dbg_watchdog"] = function()
        pcall(function()
          require("dbg.watchdog").stop()
        end)
      end
      dap.listeners.after.disconnect["dbg_watchdog"] = function()
        pcall(function()
          require("dbg.watchdog").stop()
        end)
      end

      dap.listeners.after.event_terminated["dbg_panels"] = teardown
      dap.listeners.after.disconnect["dbg_panels"] = teardown

      dap.listeners.after.event_terminated["dbg_inline"] = function()
        pcall(function()
          require("dbg.inline").clear()
        end)
      end

      require("dbg.notify").setup(dap)
      require("dbg.console").setup(dap)
      require("dbg.breakpoints").setup(dap)
      require("dbg.disasm").setup()

      vim.api.nvim_create_user_command("DbgBreak", function(o)
        if o.args ~= "" then
          require("dbg.breakpoints").toggle(o.args)
        else
          require("dbg.breakpoints").prompt()
        end
      end, { nargs = "?", desc = "Break on a function name or 0xADDRESS" })

      vim.api.nvim_create_user_command("DbgInline", function(o)
        local mode = o.args
        require("dbg.inline").toggle(mode == "" and nil or mode == "on")
      end, {
        nargs = "?",
        complete = function()
          return { "on", "off" }
        end,
        desc = "Show variable values where they are used, not only where they are declared",
      })

      vim.api.nvim_create_user_command("DbgClose", function()
        require("dbg.layout").leave()
      end, { desc = "Close every debugger window and restore the previous layout" })

      vim.api.nvim_create_user_command("DbgBreakpoints", function()
        require("dbg.breakpoints").pick()
      end, { desc = "List every breakpoint the debugger will stop on" })

      vim.api.nvim_create_user_command("DbgState", function()
        local state = require("dbg.caps").state()
        if not state then
          require("dbg.notify").info("No debug session is running")
          return
        end
        local lines = {}
        for _, feature in ipairs({
          "line_breakpoints",
          "source_stepping",
          "function_breakpoints",
          "instruction_breakpoints",
          "disassembly",
          "qemu_monitor",
        }) do
          local ok, reason = require("dbg.caps").supports(feature)
          lines[#lines + 1] = ("%-24s %s%s"):format(feature, ok and "yes" or "no", reason and ("  " .. reason) or "")
        end
        require("dbg.notify").info(
          ("%s / %s / %s / debug info: %s\n%s"):format(
            state.backend,
            state.request,
            state.kind,
            state.debug_info,
            table.concat(lines, "\n")
          )
        )
      end, { desc = "Report what this session supports and why" })

      vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
          pcall(function()
            require("dbg.session").shutdown()
          end)
        end,
        desc = "Never leave a debug adapter behind when Neovim exits",
      })

      vim.api.nvim_create_autocmd("VimResized", {
        callback = function()
          if not dap.session() then
            return
          end
          vim.schedule(function()
            pcall(function()
              require("dbg.layout").apply()
            end)
          end)
        end,
        desc = "Re-measure the debugger layout against the terminal's cell grid",
      })

      vim.api.nvim_create_autocmd({ "WinNew", "WinClosed" }, {
        callback = function()
          if not dap.session() then
            return
          end
          vim.schedule(function()
            pcall(function()
              require("dbg.layout").resize()
            end)
          end)
        end,
        desc = "Keep the side column's shares after another window reflows it",
      })

      vim.api.nvim_create_user_command("DbgTargets", function()
        require("dbg.kernel").show_report()
      end, { desc = "Report the QEMU kernel debug targets found on this machine" })

      vim.api.nvim_create_user_command("DbgKernel", function()
        require("dbg.kernel").start()
      end, { desc = "Pick a QEMU gdbstub and attach the kernel debugger" })

      vim.api.nvim_create_user_command("DbgKernelEarly", function()
        require("dbg.kernel").start({ kgdb_auto = true })
      end, { desc = "Attach with the early-boot machinery armed (GDBTOOLS_AUTO=1)" })

      vim.api.nvim_create_user_command("DbgLog", function()
        require("dbg.notify").show_log()
      end, { desc = "Everything the debugger reported, including messages that scrolled past" })

      vim.api.nvim_create_user_command("DbgLayoutReset", function()
        require("dbg.layout").rebuild()
      end, { desc = "Rebuild the debugger windows, leaving the session and breakpoints alone" })

      vim.api.nvim_create_user_command("DbgControlFlow", function()
        require("dbg.cfg").toggle_in_editor()
      end, { desc = "Show the control flow in the source window, and the source again on a second call" })

      vim.api.nvim_create_user_command("DbgMemory", function(o)
        require("dbg.memory").open(o.args)
      end, { nargs = "?", desc = "Open the DAP-driven memory view" })

      vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
        callback = function(ev)
          local ft = vim.bo[ev.buf].filetype
          if not (ft:match("^dbg%-") or ft:match("^dap%-view") or ft == "dap-repl" or ft == "dap-disassembly") then
            return
          end
          local win = vim.fn.bufwinid(ev.buf)
          if win == -1 then
            return
          end
          vim.wo[win].list = false
          vim.wo[win].number = false
          vim.wo[win].relativenumber = false
          vim.wo[win].signcolumn = "no"
          vim.wo[win].wrap = false
          if ft:match("^dbg%-") then
            vim.schedule(function()
              pcall(function()
                require("dbg.panel").enforce_unique(ev.buf)
              end)
            end)
          end
        end,
        desc = "Keep listchars and gutters out of the debugger panels, one window per panel",
      })

      vim.api.nvim_create_user_command("DbgSafeMem", function(o)
        local mode = o.args ~= "" and o.args or "auto"
        if mode ~= "on" and mode ~= "off" and mode ~= "auto" then
          vim.notify("DbgSafeMem takes on, off or auto", vim.log.levels.ERROR)
          return
        end
        require("dbg.safemem").mode = mode
        require("dbg.safemem").invalidate()
        vim.notify("Memory read guard: " .. mode, vim.log.levels.INFO)
      end, {
        nargs = "?",
        complete = function()
          return { "on", "off", "auto" }
        end,
        desc = "Guard memory reads against QEMU device-region dispatch",
      })

      vim.api.nvim_create_user_command("DbgMappings", function()
        require("dbg.mappings").open()
      end, { desc = "Show the target memory map" })

      vim.api.nvim_create_user_command("DbgLayout", function(o)
        local layout = require("dbg.layout")
        if o.args ~= "" then
          layout.preset = o.args
        end
        layout.apply()
        require("dbg.notify").info("Layout " .. layout.preset .. ": " .. layout.describe())
      end, {
        nargs = "?",
        complete = function()
          return { "auto", "wide", "compact" }
        end,
        desc = "Switch the debugger window layout",
      })

      vim.api.nvim_create_user_command("DbgRegisters", function()
        require("dbg.registers").open()
      end, { desc = "Open the DAP-driven register view" })
    end,
  },
}
