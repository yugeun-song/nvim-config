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
            -- No sections, no labels, no default here: a session with no gdb behind
            -- it gets nvim-dap-view exactly as it ships. The custom sections below
            -- only have to exist so the gdb ring can name them; dbg.context picks
            -- the ring or the stock one per session, when a session initializes and
            -- at every stop. Nothing takes the ring down when a session ends: the
            -- panels stay up to be read, so they keep the winbar that names them.
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
          -- "open", not true: the panel comes up with the session and STAYS up
          -- when it ends. What the program printed and where it stopped are worth
          -- reading after the fact, and a window that vanishes takes them with it.
          -- <leader>du closes it.
          auto_toggle = "open",
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
          if require("dbg.context").is_low_level() then
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
      {
        "<leader>dD",
        function()
          if require("dbg.context").block_if_managed("The disassembly view") then
            return
          end
          vim.cmd("DapDisasm")
        end,
        desc = "Debug: disassembly",
      },
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
      local context = require("dbg.context")

      -- The winbar of a gdb / Linux Kernel session; dbg.context only switches to it.
      context.set_low_level_winbar({
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
        show_keymap_hints = false,
        labels = {
          scopes = adaptive("Scopes(S)", "Sco(S)"),
          watches = adaptive("Watches(W)", "Wat(W)"),
          threads = adaptive("Call stack(T)", "Stk(T)"),
          breakpoints = adaptive("Breakpoints(B)", "Brk(B)"),
          repl = adaptive("gdb console(R)", "gdb(R)"),
          console = adaptive("Output(C)", "Out(C)"),
          exceptions = adaptive("Exceptions(E)", "Exc(E)"),
          sessions = adaptive("Sessions(K)", "Ses(K)"),
        },
      })

      -- nvim-dap reads .vscode/launch.json on demand; allow the comments in it.
      pcall(function()
        local vscode = require("dap.ext.vscode")
        local json = require("plenary.json")
        vscode.json_decode = function(str)
          return vim.json.decode(json.json_strip_comments(str))
        end
      end)

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

      -- The gdb panels own the window grid, so only a gdb stop jumps through the
      -- layout. Every other adapter keeps nvim-dap's own jump.
      for _, adapter in ipairs({ "gdb", "gdb_kernel" }) do
        dap.defaults[adapter].switchbuf = function(bufnr, line, column)
          require("dbg.layout").jump(bufnr, line, column)
        end
      end

      -- nvim-dap says "Source missing, cannot jump to frame" on every stop in code with
      -- no line table, which is most of a kernel's early boot: arm64 puts primary_entry
      -- and __primary_switch in .rodata.text, uncovered by this build's DWARF line
      -- table. The session already says so once and shows the disassembly instead.
      local dap_utils = require("dap.utils")
      if not dap_utils.dbg_quiet_source_missing then
        local report = dap_utils.notify
        dap_utils.notify = function(msg, ...)
          if type(msg) == "string" and msg:find("^Source missing, cannot jump to frame") and context.is_low_level() then
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
        -- Cross-arch usermode: a config that names a QEMU gdbstub -- its own via
        -- dbg_qemuser, or an external one via target -- debugs a foreign-arch
        -- binary. Read the arch from the ELF so the right cross gdb, sysroot and
        -- (for a launch) usermode QEMU follow from the binary, not from a restated
        -- constant. The plain host-arch launch/attach configs set neither, so this
        -- is a no-op for them.
        if config.program and (config.dbg_qemuser or config.target) then
          config.arch = config.arch or discover.elf_arch(config.program)
          if config.dbg_qemuser and config.qemu_port and not config.target then
            config.target = ":" .. tostring(config.qemu_port)
          end
          if config.sysroot == nil then
            config.sysroot = require("dbg.qemuser").default_sysroot(config.arch)
          end
        end
        local bin = config.gdb_bin or (config.arch and discover.gdb_for(config.arch)) or "gdb"
        local args = { "-q", "-i", "dap", "-iex", "set pagination off" }
        -- A cross target's shared libraries live under the sysroot; without it gdb
        -- resolves nothing past the main binary. QEMU is handed the same root by -L.
        if config.sysroot and config.sysroot ~= "" then
          table.insert(args, "-iex")
          table.insert(args, "set sysroot " .. config.sysroot)
        end
        local tool = discover.gdbtools_loader(config and config.program and vim.fs.dirname(config.program))
        if tool then
          table.insert(args, "-ex")
          table.insert(args, "source " .. tool)
        end
        local spec = { type = "executable", command = bin, args = args }
        if config.dbg_qemuser and config.qemu_port then
          require("dbg.qemuser").spawn(config, function()
            callback(spec)
          end, function(msg)
            require("dbg.notify").error(msg)
            callback(spec)
          end)
        else
          callback(spec)
        end
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
        -- An address an operator exported by hand outranks every derivation below;
        -- it is the documented way to override the base recovery, so remember that it
        -- came from outside before anything here writes to the same key.
        local operator_entry = env.GDBTOOLS_ENTRY_PA
        if config.kgdb_auto then
          env.GDBTOOLS_AUTO = "1"
        end
        -- The extension carries no machine constants: it debugs whatever it is
        -- pointed at. The tree describes its own machine, so read it from there
        -- rather than restating it here, where it would drift from what the shell
        -- launcher reads. Anything already in the environment wins.
        local facts = discover.machine_facts(config.kernel_root)
        -- GDBTOOLS_ENTRY_PA is the exception. The tree states the address its
        -- DEFAULT boot mode lands the kernel at; this port may be running another
        -- one. Hold it back and let the recorded run decide, exactly as the shell
        -- launcher does.
        local entry_from_tree = facts.GDBTOOLS_ENTRY_PA
        facts.GDBTOOLS_ENTRY_PA = nil
        for k, v in pairs(facts) do
          if not env[k] or env[k] == "" then
            env[k] = v
          end
        end

        -- What this port was actually started as. A firmware chain lands the kernel
        -- at an address the launcher recorded, so break there; a direct boot has no
        -- such address and the arch recovers or scans for the entry instead, which
        -- gdbtools only does while ENTRY_PA is unset.
        -- Re-read it here rather than trusting what the config carries. A config is
        -- remembered and replayed by <leader>dc, so the snapshot taken when the
        -- target was picked can describe a guest that has since been restarted in
        -- another boot mode on the same port. The shell launcher reads the file on
        -- every connect; this does the same, and falls back to the snapshot only
        -- when the target names no port to look up.
        local state = discover.run_state(tonumber(tostring(config.target or ""):match(":(%d+)$")))
          or config.run_state
        local mode = state and state.KBL_BOOT
        if (mode == "uboot" or mode == "uefi") and state.KBL_LOADADDR and state.KBL_LOADADDR ~= "" then
          if not env.GDBTOOLS_ENTRY_PA or env.GDBTOOLS_ENTRY_PA == "" then
            env.GDBTOOLS_ENTRY_PA = state.KBL_LOADADDR
          end
          -- The bootloader copies the image to that address after reset, so a
          -- software breakpoint planted there while the guest is frozen is
          -- overwritten before the CPU ever arrives.
          if not env.GDBTOOLS_BREAK_KIND or env.GDBTOOLS_BREAK_KIND == "" then
            env.GDBTOOLS_BREAK_KIND = "hw"
          end
        elseif entry_from_tree then
          -- Direct boot, or nothing recorded for this port. The address the tree
          -- states describes the mode the tree defaults to, so it holds only while
          -- that is the mode actually running; otherwise leave the entry unstated
          -- and let the architecture discover it.
          local stated = discover.tree_value(config.kernel_root, "BOOT")
          if not stated or stated == "" then
            stated = "direct"
          end
          if (mode or stated) == stated and (not env.GDBTOOLS_ENTRY_PA or env.GDBTOOLS_ENTRY_PA == "") then
            env.GDBTOOLS_ENTRY_PA = entry_from_tree
          end
        end
        -- The compressed image is what both KASLR recoveries read: the direct one
        -- walks the decompressor's stages, the UEFI one takes its symbol offsets and
        -- the signature it searches for from it. Where it sits relative to the build
        -- tree is our fact to supply, not something for it to guess.
        -- x86_64 only: the recoveries below are written against the 64-bit boot
        -- path, and a 32-bit kernel neither relocates the same way nor hands over
        -- through the same stub.
        -- The port's own run state answers which boot is running; with none
        -- recorded the tree's stated default does, and a tree that states nothing
        -- boots direct. The shell launcher resolves it the same way, so a terminal
        -- and an editor session send gdbtools down the same recovery.
        local eff_boot = mode
        if not eff_boot or eff_boot == "" then
          eff_boot = discover.tree_value(config.kernel_root, "BOOT")
        end
        if not eff_boot or eff_boot == "" then
          eff_boot = "direct"
        end
        local firmware_boot = eff_boot == "uboot" or eff_boot == "uefi"
        if config.kernel_root and config.arch == "x86_64" then
          local decomp = config.kernel_root .. "/arch/x86/boot/compressed/vmlinux"
          if vim.uv.fs_stat(decomp) then
            if not env.GDBTOOLS_X86_DECOMP_VMLINUX then
              env.GDBTOOLS_X86_DECOMP_VMLINUX = decomp
            end
            -- 0x100000 belongs to the x86 boot protocol, not to QEMU:
            -- Documentation/arch/x86/boot.rst states it as the load address of a
            -- bzImage's protected-mode kernel, and every loader honouring
            -- LOADED_HIGH puts the decompressor there -- QEMU's `-kernel`, and GRUB
            -- on real hardware alike. A protocol constant, not a hardware
            -- guarantee: a loader that ignores the protocol may put it elsewhere.
            -- The KASLR base recovery breaks there. The shell launcher states the
            -- same value, so an editor session gets the same recovery.
            -- Only for a direct boot: a firmware chain loads the image as PE,
            -- wherever its allocator chose, and gdbtools finds that by searching.
            if not firmware_boot and not env.GDBTOOLS_X86_DECOMP_PA then
              env.GDBTOOLS_X86_DECOMP_PA = "0x100000"
            end
          end
        end
        -- x86 needs this in the process environment, not as a command: the
        -- randomized base is recovered while the session starts.
        --
        -- Whether the guest runs with KASLR is a fact about the GUEST, not about the
        -- mode the editor picked. Gating it on the early-boot pick handed a terminal
        -- session and an editor session different environments for the same guest, so
        -- the evidence is read in the launcher's order: the recorded run first, then
        -- what target discovery scored, with "cannot tell" counting as on.
        local kaslr_on
        if state and state.KBL_KASLR and state.KBL_KASLR ~= "" then
          kaslr_on = state.KBL_KASLR == "1"
        else
          kaslr_on = (config.kaslr_state or "unknown") ~= "off"
        end
        if config.arch == "x86_64" and kaslr_on then
          env.GDBTOOLS_X86_KASLR = "1"
          -- Under KASLR the kernel sits at a randomized physical base, so every
          -- address derived above is wrong AND, being set, it suppresses the base
          -- recovery (gdbtools runs that only when ENTRY_PA is unset). Take it back --
          -- the shell launcher does the same -- unless an operator pinned one.
          if not operator_entry or operator_entry == "" then
            env.GDBTOOLS_ENTRY_PA = nil
          end
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
        {
          -- Launch a foreign-arch binary under this editor's own usermode QEMU and
          -- attach to it. QEMU freezes the guest at its entry until gdb connects,
          -- so the session opens stopped at _start; drive it from there with the
          -- gutter breakpoints and <leader>dc.
          name = "Run on QEMU user (cross-arch)",
          type = "gdb",
          request = "attach",
          dbg_qemuser = true,
          program = input_path("Guest executable: ", cwd_exe),
          qemu_args = input_args("Guest arguments: "),
          qemu_port = function()
            return tonumber(vim.fn.input("QEMU gdbstub port: ", "1234"))
          end,
        },
        {
          -- Attach to a usermode QEMU the user already launched, e.g.
          --   qemu-aarch64 -g 1234 -L /usr/aarch64-linux-gnu ./a.out
          -- The binary is read for symbols; the arch and sysroot follow from it.
          name = "Attach to a QEMU user gdbstub (cross-arch)",
          type = "gdb",
          request = "attach",
          program = input_path("Guest executable (for symbols): ", cwd_exe),
          target = function()
            local t = vim.trim(vim.fn.input("gdbstub (host:port or :port): ", ":1234"))
            if t:match("^%d+$") then
              t = ":" .. t
            end
            return t
          end,
        },
      }

      dap.configurations.c = c_configs
      dap.configurations.cpp = c_configs
      dap.configurations.asm = c_configs

      -- A launched usermode QEMU is this editor's to stop: tear down exactly the
      -- one this session started when the session ends. jobstart also terminates
      -- it on nvim exit, so quitting never leaks one either.
      local function stop_qemuser(session)
        local port = session and session.config and session.config.qemu_port
        if port then
          require("dbg.qemuser").stop(tonumber(port))
        end
      end
      dap.listeners.after.event_terminated["dbg_qemuser"] = stop_qemuser
      dap.listeners.after.event_exited["dbg_qemuser"] = stop_qemuser
      dap.listeners.after.disconnect["dbg_qemuser"] = stop_qemuser

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
          -- The gdb-console behaviour (send the line under the cursor to gdb) is for
          -- gdb sessions; a managed adapter keeps nvim-dap's own REPL.
          if not context.is_low_level() then
            return
          end
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

      -- Several sessions can run at once, so the panels stay up as long as any gdb
      -- one is alive.
      local function low_level_session_running()
        for _, s in pairs(dap.sessions() or {}) do
          if context.is_low_level(s) then
            return true
          end
        end
        return false
      end

      -- nvim-dap settles on a frame only once the stackTrace response lands, so paint
      -- from that response and not from the stopped event: reading `current_frame` any
      -- earlier gets the previous stop's.
      local awaiting = {}

      local function paint(session)
        if dap.session() ~= session then
          return
        end
        if not context.is_low_level(session) then
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

      -- Keep the winbar in step with whichever session is active, so switching
      -- between a managed and a gdb session shows the right sections. Runs for
      -- every profile; the gdb-only painting below stays gated.
      dap.listeners.after.event_stopped["dbg_winbar"] = function(session)
        if require("dap").session() == session then
          pcall(function()
            context.apply_winbar(session)
          end)
        end
      end

      dap.listeners.after.event_stopped["dbg_panels"] = function(session, body)
        if not context.is_low_level(session) then
          return
        end
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
        if not context.is_low_level(session) then
          return
        end
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

      local function snapshot_layout(session)
        if not context.is_low_level(session) then
          return
        end
        pcall(function()
          require("dbg.layout").snapshot()
        end)
      end

      dap.listeners.after.initialize["dbg_panels"] = snapshot_layout
      dap.listeners.before.event_initialized["dbg_panels"] = snapshot_layout

      dap.listeners.after.event_initialized["dbg_panels"] = function(session)
        pcall(function()
          -- Winbar follows the profile for every session, so a managed one shows
          -- nvim-dap-view's own sections instead of the gdb/kernel panels.
          context.apply_winbar(session)
          require("dbg.caps").invalidate(session)
          require("dbg.session").remember(session.config)
          if not context.is_low_level(session) then
            -- DbgLayout can build the panels with no session up, and they would
            -- otherwise stay on screen through a session that has no gdb behind it.
            if not low_level_session_running() then
              require("dbg.layout").drop_panels()
            end
            return
          end
          require("dbg.layout").enter()
          local kernel = require("dbg.kernel")
          kernel.load_firmware_symbols(session, function()
            kernel.arm_kaslr(session)
          end)
          kernel.watch_target(session)
        end)
      end

      -- Ending a session drops what the session held, and nothing else. The windows
      -- stay exactly as they were: the last stop, the console and the program's output
      -- are the things you read after it finishes. :DbgClose puts the layout back, and
      -- <leader>du closes the panel; both are asked for.
      local function teardown(session)
        pcall(function()
          require("dbg.caps").invalidate(session)
          require("dbg.kernel").stop_watchdog()
        end)
      end

      -- Losing the QEMU gdbstub does not terminate the DAP session, so nothing
      -- would otherwise say the panels have gone stale.
      -- A binary with no DWARF is a normal thing to attach to; it is only worth
      -- saying once, at the start, so the panels are read for what they can
      -- actually show.  Nothing is rebuilt and nothing is disabled beyond what
      -- the missing information already makes impossible.
      dap.listeners.after.event_initialized["dbg_debuginfo"] = function(session)
        if not context.is_low_level(session) then
          return
        end
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
        if not context.is_kernel(session) then
          return
        end
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
        if context.block_if_managed_session("Inline values") then
          return
        end
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
        if context.block_if_managed_session("The debugger layout") then
          return
        end
        require("dbg.layout").leave()
      end, { desc = "Close every debugger window and restore the previous layout" })

      vim.api.nvim_create_user_command("DbgBreakpoints", function()
        require("dbg.breakpoints").pick()
      end, { desc = "List every breakpoint the debugger will stop on" })

      vim.api.nvim_create_user_command("DbgState", function()
        if context.block_if_managed_session("This report") then
          return
        end
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
          if not context.is_low_level() then
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
          if not context.is_low_level() then
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
        if context.block_if_managed_session("The debugger layout") then
          return
        end
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
        if context.block_if_managed_session("The memory read guard") then
          return
        end
        local mode = o.args ~= "" and o.args or "auto"
        if mode ~= "on" and mode ~= "off" and mode ~= "auto" then
          vim.notify("DbgSafeMem takes on, off or auto", vim.log.levels.ERROR)
          return
        end
        require("dbg.qemumon").mode = mode
        require("dbg.qemumon").invalidate()
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
        if context.block_if_managed_session("The debugger layout") then
          return
        end
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
