-- nvim-dap set up for this configuration: the gdb and LLDB adapters and their launch configurations, the panels,
-- the winbar and the session listeners. lua/plugins/debugging/debug_adapter.lua loads it together with nvim-dap.
local M = {}

local last_answer = {}

-- Keep asking until the answer is runnable; a typo would otherwise be remembered
-- and replayed by every later <leader>dc.
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
  local win = vim.fn.has("win32") == 1

  local function escape_at(at)
    return line:sub(at, at) == "\\" and at < n and (not win or line:sub(at + 1, at + 1) == '"')
  end

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
        if escape_at(i) then
          i = i + 1
        end

        cur[#cur + 1] = line:sub(i, i)
        i = i + 1
      end
    elseif escape_at(i) then
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

-- nvim-dap-view's options: its winbar sections are this configuration's panels.
function M.dap_view_options()
  return {
    winbar = {
      show = true,
      -- No sections or default: a session without gdb gets nvim-dap-view as it ships. dbg.context picks
      -- the gdb ring or the stock one per session; the ring stays up after the session ends.
      custom_sections = {
        watch = {
          label = adaptive("Locals+Globals(A)", "Var(A)"),
          keymap = "A",
          action = function()
            require("features.debugging.views.watch_expressions").probe()
          end,
          buffer = function()
            return require("features.debugging.views.watch_expressions").buffer()
          end,
        },
        registers = {
          label = adaptive("Registers(G)", "Reg(G)"),
          keymap = "G",
          action = function()
            require("features.debugging.views.registers").render()
          end,
          buffer = function()
            return require("features.debugging.views.registers").buffer()
          end,
        },
        memory = {
          label = adaptive("Memory(M)", "Mem(M)"),
          keymap = "M",
          action = function()
            require("features.debugging.views.memory").refresh()
          end,
          buffer = function()
            return require("features.debugging.views.memory").buffer()
          end,
        },
        mappings = {
          label = adaptive("Mappings(V)", "Map(V)"),
          keymap = "V",
          action = function()
            require("features.debugging.views.memory_mappings").probe()
          end,
          buffer = function()
            return require("features.debugging.views.memory_mappings").buffer()
          end,
        },
        controlflow = {
          label = adaptive("Control flow(F)", "CFG(F)"),
          keymap = "F",
          action = function()
            require("features.debugging.views.control_flow_graph").probe()
          end,
          buffer = function()
            return require("features.debugging.views.control_flow_graph").buffer()
          end,
        },
        session = {
          label = adaptive("Target(I)", "Tgt(I)"),
          keymap = "I",
          action = function()
            require("features.debugging.sessions.target_session").probe()
          end,
          buffer = function()
            return require("features.debugging.sessions.target_session").buffer()
          end,
        },
      },
    },
    windows = {
      size = 0.34,
      position = "below",
      terminal = { position = "left", hide = { "gdb", "gdb_linux_kernel", "gdb_kernel" } },
    },
    virtual_text = { enabled = true },
    -- "open", not true: the panel stays up when the session ends so its
    -- output can be read; <leader>du closes it.
    auto_toggle = "open",
  }
end

function M.setup()
  local dap = require("dap")
  local discover = require("features.debugging.sessions.discovery")
  local context = require("features.debugging.sessions.session_profile")
  local group = vim.api.nvim_create_augroup("dbg", { clear = true })

  local labels = {
    scopes = adaptive("Scopes(S)", "Sco(S)"),
    watches = adaptive("Watches(W)", "Wat(W)"),
    threads = adaptive("Call stack(T)", "Stk(T)"),
    breakpoints = adaptive("Breakpoints(B)", "Brk(B)"),
    repl = adaptive("gdb console(R)", "gdb(R)"),
    console = adaptive("Output(C)", "Out(C)"),
    exceptions = adaptive("Exceptions(E)", "Exc(E)"),
    sessions = adaptive("Sessions(K)", "Ses(K)"),
  }

  -- The winbar of a gdb / Linux Kernel session; dbg.context only switches to it.
  context.set_gdb_winbar({
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
    labels = labels,
  })

  -- An LLDB session keeps the panels that speak plain DAP; the others run gdb commands.
  context.set_lldb_winbar({
    sections = {
      "scopes",
      "watches",
      "registers",
      "memory",
      "disassembly",
      "threads",
      "breakpoints",
      "repl",
      "console",
    },
    default_section = "scopes",
    show_keymap_hints = false,
    labels = vim.tbl_extend("force", labels, { repl = adaptive("LLDB console(R)", "lldb(R)") }),
  })

  -- The panels are winfixbuf, so bufferline's keys raise E1513 from inside
  -- one. Wrap the commands rather than rebinding keys.
  pcall(function()
    local commands = require("bufferline.commands")

    for _, name in ipairs({ "go_to", "cycle", "pick", "move", "exec" }) do
      local original = commands[name]

      if type(original) == "function" and not commands["dbg_wrapped_" .. name] then
        commands["dbg_wrapped_" .. name] = true
        commands[name] = function(...)
          require("features.debugging.views.layout").unfix_for_buffer_switch()

          return original(...)
        end
      end
    end
  end)

  -- Only a stop in a session with the panels jumps through the layout; other adapters keep nvim-dap's.
  for _, adapter in ipairs({ "gdb", "gdb_linux_kernel", "gdb_kernel", "lldb" }) do
    dap.defaults[adapter].switchbuf = function(bufnr, line, column)
      require("features.debugging.views.layout").jump(bufnr, line, column)
    end
  end

  -- nvim-dap warns "Source missing" on every stop without a line table, which
  -- is most of early boot. The session says so once and shows disassembly.
  local dap_utils = require("dap.utils")

  if not dap_utils.dbg_quiet_source_missing then
    local report = dap_utils.notify

    rawset(dap_utils, "notify", function(msg, ...)
      if type(msg) == "string" and msg:find("^Source missing, cannot jump to frame") and context.has_panels() then
        return
      end

      return report(msg, ...)
    end)

    dap_utils.dbg_quiet_source_missing = true
  end

  local warned = {}

  -- Same toolkit as the kernel adapter: the control-flow backend is generic,
  -- and the kernel-only commands stay inert without a vmlinux.
  dap.adapters.gdb = function(callback, config)
    local notify = require("features.debugging.sessions.notifications")

    -- Cross-arch usermode (dbg_qemuser or an external target): the ELF gives the arch, which picks gdb,
    -- sysroot and QEMU. Host-arch configs set neither.
    if config.program and (config.dbg_qemuser or config.target) then
      config.arch = config.arch or discover.elf_arch(config.program)
      if config.dbg_qemuser and not config.target then
        config.qemu_socket = require("features.debugging.qemu.user_mode").socket_path()
        config.target = config.qemu_socket
      end

      if config.sysroot == nil then
        config.sysroot = require("features.debugging.qemu.user_mode").default_sysroot(config.arch)
      end
    end

    -- The host's own gdb debugs host programs; another arch needs one built for it.
    local bin, why, broken = config.gdb_bin, nil, nil

    if bin then
      local ok

      ok, why = discover.gdb_supports_dap(bin)
      if not ok then
        bin = nil
      end
    else
      bin, why, broken = discover.gdb_for(config.arch)
    end

    if not bin then
      notify.error(why)

      return
    end

    for _, note in ipairs(broken or {}) do
      if not warned[note] then
        warned[note] = true
        notify.warn("skipped " .. note)
      end
    end

    local args = { "-q", "-i", "dap", "-iex", "set pagination off" }

    -- Without the sysroot gdb resolves nothing past the main binary; QEMU
    -- gets the same root by -L.
    if config.sysroot and config.sysroot ~= "" then
      table.insert(args, "-iex")
      table.insert(args, "set sysroot " .. config.sysroot)
    end

    local tool, terr = discover.gdbtools_loader()

    if terr then
      notify.error(terr)

      return
    end

    if tool then
      table.insert(args, "-ex")
      table.insert(args, "source " .. tool)
    end

    local spec = { type = "executable", command = bin, args = args }

    if config.dbg_qemuser and config.qemu_socket then
      -- A gdb attached to a QEMU that never started would wait forever; say why and start nothing.
      require("features.debugging.qemu.user_mode").spawn(config, function()
        callback(spec)
      end, function(msg)
        notify.error(msg)
      end)
    else
      callback(spec)
    end
  end

  -- kbuildlab describes the kernel session (gdb, -iex lines that trust the tree's scripts/gdb, gdbtools facts,
  -- vmlinux), asked afresh at every start. Without kbuildlab there is no kernel session.
  dap.adapters.gdb_linux_kernel = function(callback, config)
    local notify = require("features.debugging.sessions.notifications")
    local kbl = config.kbl or {}

    if not (type(kbl.tree) == "string" and kbl.tree ~= "" and tonumber(kbl.port)) then
      notify.error("This Linux kernel configuration names no kbuildlab tree and port; start it with :DbgLinuxKernel")

      return
    end

    local args = { "attach", kbl.tree, "--port", tostring(kbl.port), "--json" }
    -- "Attach now" leaves gdbtools inert until `kearly on`.
    local env = { GDBTOOLS_AUTO = config.kgdb_auto and "1" or "0" }

    discover.kbuildlab_json(args, env, function(spec, why)
      if not spec then
        notify.error(why)

        return
      end

      local dap_ok, dap_why = discover.gdb_supports_dap(spec.gdb or "gdb")

      if not dap_ok then
        notify.error(dap_why)

        return
      end

      config.program = spec.vmlinux
      config.target = spec.target
      config.kernel_root = spec.src
      -- The ELF's name for it (aarch64, not the kernel's arm64), as for programs.
      config.arch = discover.elf_arch(spec.vmlinux or "") or spec.arch
      config.boot = spec.boot
      config.fwsym = spec.fwsym
      config.qemu_pid = spec.pid
      config.gdb_bin = spec.gdb
      config.kaslr_state = spec.kaslr == true and "on" or (spec.kaslr == false and "off" or "unknown")
      local gargs = { "-q", "-i", "dap" }

      for _, x in ipairs(spec.iex or {}) do
        vim.list_extend(gargs, { "-iex", x })
      end

      if spec.gdbtools then
        vim.list_extend(gargs, { "-ex", "source " .. spec.gdbtools })
      end

      local genv = vim.fn.environ()

      for k, v in pairs(spec.env or {}) do
        genv[k] = v
      end

      local env_list = {}

      for k, v in pairs(genv) do
        if k:find("^[^=]*$") then
          env_list[#env_list + 1] = k .. "=" .. tostring(v)
        end
      end

      callback({
        type = "executable",
        command = spec.gdb,
        args = gargs,
        -- The attach answers once gdb has read vmlinux, 9-11 s here; 4 s warns every time.
        options = { env = env_list, initialize_timeout_sec = 60 },
      })
    end)
  end

  -- Launch configurations written before the adapter said which kernel call it gdb_kernel.
  dap.adapters.gdb_kernel = dap.adapters.gdb_linux_kernel

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
      -- QEMU freezes the guest at its entry until gdb connects, so the
      -- session opens stopped at _start.
      name = "Run on QEMU user (cross-arch)",
      type = "gdb",
      request = "attach",
      dbg_qemuser = true,
      program = input_path("Guest executable: ", cwd_exe),
      qemu_args = input_args("Guest arguments: "),
    },
    {
      -- e.g. qemu-aarch64 -g 1234 -L /usr/aarch64-linux-gnu ./a.out
      name = "Attach to a QEMU user gdbstub (cross-arch)",
      type = "gdb",
      request = "attach",
      program = input_path("Guest executable (for symbols): ", cwd_exe),
      qemu_user = true,
      target = function()
        local t = vim.trim(vim.fn.input("gdbstub (socket path, host:port or :port): ", ":1234"))

        if t:match("^%d+$") then
          t = ":" .. t
        end

        return t
      end,
    },
  }

  if vim.fn.has("linux") == 0 then
    c_configs = vim.tbl_filter(function(c)
      return not (c.dbg_qemuser or c.qemu_user)
    end, c_configs)
  end

  -- macOS debugs C and C++ through LLDB (gdb cannot on Apple silicon); Windows offers it beside gdb, for MSVC
  -- builds whose PDB gdb cannot read; vim.g.dbg_lldb offers it elsewhere.
  if vim.fn.has("mac") == 1 or vim.fn.has("win32") == 1 or vim.g.dbg_lldb then
    dap.adapters.lldb = function(callback)
      local cmd, why = discover.lldb()

      if not cmd then
        require("features.debugging.sessions.notifications").error(why)

        return
      end

      callback({ type = "executable", command = cmd })
    end

    -- codelldb evaluates C expressions only with expressions = "native"; lldb-dap always does and ignores it.
    local lldb_configs = {
      {
        name = "Launch executable (lldb)",
        type = "lldb",
        request = "launch",
        program = input_path("Executable: ", cwd_exe),
        args = input_args("Arguments: "),
        cwd = "${workspaceFolder}",
        expressions = "native",
      },
      {
        name = "Launch executable, stop at main (lldb)",
        type = "lldb",
        request = "launch",
        program = input_path("Executable: ", cwd_exe),
        args = input_args("Arguments: "),
        cwd = "${workspaceFolder}",
        preRunCommands = { "breakpoint set --one-shot true --name main" },
        expressions = "native",
      },
      {
        name = "Attach to a running process (lldb)",
        type = "lldb",
        request = "attach",
        expressions = "native",
        program = input_path("Executable: ", cwd_exe),
        pid = function()
          return tonumber(vim.fn.input("PID: "))
        end,
      },
    }

    c_configs = vim.list_extend(discover.apple_silicon and {} or c_configs, lldb_configs)
  end

  dap.configurations.c = c_configs
  dap.configurations.cpp = c_configs
  dap.configurations.asm = c_configs

  -- Stop exactly the usermode QEMU this session started; jobstart also
  -- terminates it on nvim exit.
  local function stop_qemuser(session)
    local sock = session and session.config and session.config.qemu_socket

    if sock then
      require("features.debugging.qemu.user_mode").stop(sock)
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

  -- Labelled "gdb console", so <CR> sends the line under the cursor to GDB
  -- instead of nvim-dap's variable expansion.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "dap-repl",
    callback = function(ev)
      -- A managed adapter keeps nvim-dap's own REPL.
      if not context.is_gdb() then
        return
      end

      local buf = ev.buf

      -- blink.cmp completes dap-repl from buffer words; a command line wants
      -- no popup. GDB's own completion is still <C-x><C-o> via omnifunc.
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
      group = group,
      pattern = { "dap-repl", "dap-view-term" },
      callback = function(ev)
        pcall(colorizer.automatically, ev.buf)
      end,
      desc = "Colorize ANSI output from gdb / pwndbg in the debug console",
    })
  end

  require("features.debugging.views.highlight_groups").setup_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      require("features.debugging.views.highlight_groups").setup_highlights()
    end,
    desc = "Keep the debugger panel highlights defined across colorscheme changes",
  })

  local function gdb_session_running()
    for _, s in pairs(dap.sessions() or {}) do
      if context.has_panels(s) then
        return true
      end
    end

    return false
  end

  -- Paint from the stackTrace response, not the stopped event: before it
  -- lands, `current_frame` is the previous stop's.
  local awaiting = {}

  local PANELS = {
    registers = function()
      require("features.debugging.views.registers").render()
    end,
    watch = function()
      require("features.debugging.views.watch_expressions").probe()
    end,
    memory = function()
      require("features.debugging.views.memory").on_stopped()
    end,
    session = function()
      require("features.debugging.sessions.target_session").probe()
    end,
    mappings = function()
      require("features.debugging.views.memory_mappings").probe()
    end,
    cfg = function()
      require("features.debugging.views.control_flow_graph").probe()
    end,
  }

  local LLDB_PANELS = { registers = true, memory = true }

  local function allowed(key, session)
    return not context.is_lldb(session) or LLDB_PANELS[key] == true
  end

  local dirty = {}

  local function refresh_panels(session)
    local panel = require("features.debugging.views.buffers_and_windows")

    for key, refresh in pairs(PANELS) do
      if not allowed(key, session) then
        dirty[key] = nil
      elseif panel.visible(key) then
        dirty[key] = nil
        pcall(refresh)
      else
        dirty[key] = true
      end
    end
  end

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    pattern = "dbg://*",
    callback = function(ev)
      local key = ev.file:match("^dbg://(.+)$")

      if key and dirty[key] and dap.session() and allowed(key, dap.session()) then
        dirty[key] = nil
        vim.schedule(function()
          pcall(PANELS[key])
        end)
      end
    end,
    desc = "Refresh a debugger panel that missed stops while hidden",
  })

  local function paint(session)
    if dap.session() ~= session then
      return
    end

    if not context.has_panels(session) then
      return
    end

    refresh_panels(session)
    pcall(function()
      require("features.debugging.views.layout").resize()
      if not require("features.debugging.sessions.console").has_source(session.current_frame) then
        pcall(vim.fn.sign_unplace, session.sign_group)
        require("features.debugging.views.layout").show_disassembly()
      end
    end)

    -- nvim-dap-disasm only redraws on the scopes response while on screen;
    -- ask it directly once the window is settled.
    vim.schedule(function()
      pcall(function()
        require("dap-disasm").refresh()
      end)

      vim.defer_fn(function()
        pcall(function()
          require("features.debugging.views.disassembly").mark(session)
        end)
      end, 250)
    end)
  end

  -- Winbar follows the active session's profile; the gdb-only painting
  -- below stays gated.
  dap.listeners.after.event_stopped["dbg_winbar"] = function(session)
    if require("dap").session() == session then
      pcall(function()
        context.apply_winbar(session)
      end)
    end
  end

  dap.listeners.after.event_stopped["dbg_panels"] = function(session, body)
    if not context.has_panels(session) then
      return
    end

    pcall(function()
      require("features.debugging.views.registers").mark_stop()
    end)

    -- dbg.session.focus continues this thread.
    if body and body.threadId then
      session["dbg_stopped_thread"] = body.threadId
    end

    awaiting[session.id] = true
  end

  dap.listeners.after.stackTrace["dbg_panels"] = function(session, err, _, payload)
    if not context.has_panels(session) then
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
      -- Back to frame 0 before anything reads it, or the panels describe the caller.
      pcall(function()
        require("features.debugging.sessions.console").realign(session)
      end)
    end

    vim.schedule(function()
      paint(session)
    end)
  end

  local function snapshot_layout(session)
    if not context.has_panels(session) then
      return
    end

    pcall(function()
      require("features.debugging.views.layout").snapshot()
    end)
  end

  dap.listeners.after.initialize["dbg_panels"] = snapshot_layout
  dap.listeners.before.event_initialized["dbg_panels"] = snapshot_layout

  dap.listeners.after.event_initialized["dbg_panels"] = function(session)
    pcall(function()
      -- GDB's DAP mishandles a negative instructionOffset and codelldb rejects the -0 a zero one encodes to,
      -- so only gdb starts the disassembly at the pc.
      require("dap-disasm").set_memref(nil, context.is_gdb(session) and -1 or 16)
    end)

    pcall(function()
      context.apply_winbar(session)
      require("features.debugging.sessions.target_capabilities").invalidate(session)
      require("features.debugging.sessions.target_session").remember(session.config)
      if not context.has_panels(session) then
        -- DbgLayout may have built the panels with no session up.
        if not gdb_session_running() then
          require("features.debugging.views.layout").drop_panels()
        end

        return
      end

      require("features.debugging.views.layout").enter()
      if context.is_gdb(session) then
        require("features.debugging.linux_kernel.kbuildlab_guests").after_attach(session)
      end
    end)
  end

  -- Ending a session leaves the windows as they were, to be read;
  -- :DbgClose and <leader>du are explicit.
  local function teardown(session)
    pcall(function()
      require("features.debugging.sessions.target_capabilities").invalidate(session)
      require("features.debugging.linux_kernel.kbuildlab_guests").stop_watchdog()
    end)
  end

  -- Losing the gdbstub does not terminate the DAP session, so say so.
  dap.listeners.after.event_initialized["dbg_watchdog"] = function(session)
    if not context.is_linux_kernel(session) then
      return
    end

    pcall(function()
      require("features.debugging.sessions.gdbstub_watchdog").start(session)
    end)
  end

  dap.listeners.after.event_output["dbg_watchdog"] = function(_, body)
    pcall(function()
      require("features.debugging.sessions.gdbstub_watchdog").saw_text(body and body.output)
    end)
  end

  dap.listeners.after.event_terminated["dbg_watchdog"] = function()
    pcall(function()
      require("features.debugging.sessions.gdbstub_watchdog").stop()
    end)
  end

  dap.listeners.after.disconnect["dbg_watchdog"] = function()
    pcall(function()
      require("features.debugging.sessions.gdbstub_watchdog").stop()
    end)
  end

  dap.listeners.after.event_terminated["dbg_panels"] = teardown
  dap.listeners.after.disconnect["dbg_panels"] = teardown

  dap.listeners.after.event_terminated["dbg_inline"] = function()
    pcall(function()
      require("features.debugging.views.inline_values").clear()
    end)
  end

  require("features.debugging.sessions.notifications").setup(dap)
  require("features.debugging.sessions.console").setup(dap)
  require("features.debugging.sessions.function_and_address_breakpoints").setup(dap)
  require("features.debugging.sessions.all_stop_remote").setup(dap)
  require("features.debugging.sessions.gdb_adapter").setup(dap)
  require("features.debugging.views.disassembly").setup()

  vim.api.nvim_create_user_command("DbgBreak", function(o)
    if o.args ~= "" then
      require("features.debugging.sessions.function_and_address_breakpoints").toggle(o.args)
    else
      require("features.debugging.sessions.function_and_address_breakpoints").prompt()
    end
  end, { nargs = "?", desc = "Break on a function name or 0xADDRESS" })

  vim.api.nvim_create_user_command("DbgInline", function(o)
    if context.block_unless_gdb_session("Inline values") then
      return
    end

    local mode = o.args

    require("features.debugging.views.inline_values").toggle(mode == "" and nil or mode == "on")
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

    require("features.debugging.views.layout").leave()
  end, { desc = "Close every debugger window and restore the previous layout" })

  vim.api.nvim_create_user_command("DbgBreakpoints", function()
    require("features.debugging.sessions.function_and_address_breakpoints").pick()
  end, { desc = "List every breakpoint the debugger will stop on" })

  vim.api.nvim_create_user_command("DbgState", function()
    if context.block_if_managed_session("This report") then
      return
    end

    local state = require("features.debugging.sessions.target_capabilities").state()

    if not state then
      require("features.debugging.sessions.notifications").info("No debug session is running")

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
      local ok, reason = require("features.debugging.sessions.target_capabilities").supports(feature)

      lines[#lines + 1] = ("%-24s %s%s"):format(feature, ok and "yes" or "no", reason and ("  " .. reason) or "")
    end

    require("features.debugging.sessions.notifications").info(
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
    group = group,
    callback = function()
      pcall(function()
        require("features.debugging.sessions.target_session").shutdown()
      end)
    end,
    desc = "Never leave a debug adapter behind when Neovim exits",
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if not context.is_gdb() then
        return
      end

      vim.schedule(function()
        pcall(function()
          require("features.debugging.views.layout").apply()
        end)
      end)
    end,
    desc = "Re-measure the debugger layout against the terminal's cell grid",
  })

  vim.api.nvim_create_autocmd({ "WinNew", "WinClosed" }, {
    group = group,
    callback = function()
      if not context.is_gdb() then
        return
      end

      vim.schedule(function()
        pcall(function()
          require("features.debugging.views.layout").resize()
        end)
      end)
    end,
    desc = "Keep the side column's shares after another window reflows it",
  })

  vim.api.nvim_create_user_command("DbgTargets", function()
    require("features.debugging.linux_kernel.kbuildlab_guests").show_report()
  end, { desc = "Report the guests kbuildlab sees on this machine" })

  vim.api.nvim_create_user_command("DbgLinuxKernel", function()
    require("features.debugging.linux_kernel.kbuildlab_guests").start()
  end, { desc = "Pick a kbuildlab guest and attach the Linux kernel debugger" })

  vim.api.nvim_create_user_command("DbgLinuxKernelEarly", function()
    require("features.debugging.linux_kernel.kbuildlab_guests").start({ kgdb_auto = true })
  end, { desc = "Attach with the early-boot machinery armed (GDBTOOLS_AUTO=1)" })

  vim.api.nvim_create_user_command("DbgLog", function()
    require("features.debugging.sessions.notifications").show_log()
  end, { desc = "Everything the debugger reported, including messages that scrolled past" })

  vim.api.nvim_create_user_command("DbgLayoutReset", function()
    if context.block_if_managed_session("The debugger layout") then
      return
    end

    require("features.debugging.views.layout").rebuild()
  end, { desc = "Rebuild the debugger windows, leaving the session and breakpoints alone" })

  vim.api.nvim_create_user_command("DbgControlFlow", function()
    require("features.debugging.views.control_flow_graph").toggle_in_editor()
  end, { desc = "Show the control flow in the source window, and the source again on a second call" })

  vim.api.nvim_create_user_command("DbgMemory", function(o)
    require("features.debugging.views.memory").open(o.args)
  end, { nargs = "?", desc = "Open the DAP-driven memory view" })

  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = group,
    callback = function(ev)
      local ft = vim.bo[ev.buf].filetype

      if not require("features.debugging.views.buffers_and_windows").is_debug_ft(ft) then
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
            require("features.debugging.views.buffers_and_windows").enforce_unique(ev.buf)
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
      require("features.debugging.sessions.notifications").error("DbgSafeMem takes on, off or auto")

      return
    end

    require("features.debugging.qemu.monitor").mode = mode
    require("features.debugging.qemu.monitor").invalidate()
    require("features.debugging.sessions.notifications").info("Memory read guard: " .. mode)
  end, {
    nargs = "?",
    complete = function()
      return { "on", "off", "auto" }
    end,
    desc = "Guard memory reads against QEMU device-region dispatch",
  })

  vim.api.nvim_create_user_command("DbgMappings", function()
    require("features.debugging.views.memory_mappings").open()
  end, { desc = "Show the target memory map" })

  vim.api.nvim_create_user_command("DbgLayout", function(o)
    if context.block_if_managed_session("The debugger layout") then
      return
    end

    local layout = require("features.debugging.views.layout")

    if o.args ~= "" then
      layout.preset = o.args
    end

    layout.apply()
    require("features.debugging.sessions.notifications").info("Layout " .. layout.preset .. ": " .. layout.describe())
  end, {
    nargs = "?",
    complete = function()
      return { "auto", "wide", "compact" }
    end,
    desc = "Switch the debugger window layout",
  })

  vim.api.nvim_create_user_command("DbgRegisters", function()
    require("features.debugging.views.registers").open()
  end, { desc = "Open the DAP-driven register view" })
end

return M
