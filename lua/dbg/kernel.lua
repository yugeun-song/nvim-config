local D = require("dbg.discover")

local M = {}

local function pad(s, width)
  s = tostring(s or "")
  local w = vim.fn.strdisplaywidth(s)
  if w >= width then
    return s
  end
  return s .. string.rep(" ", width - w)
end

local function short(path)
  if not path then
    return "-"
  end
  local home = vim.uv.os_homedir()
  if home and path:sub(1, #home) == home then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

function M.candidates()
  local listen, established = D.tcp_states()
  local out = {}
  for _, inst in ipairs(D.qemu_instances()) do
    if inst.gdb_port or inst.gdb_other then
      local c = { qemu = inst, notes = {} }
      local root, root_src = D.kernel_root_from_image(inst.kernel_image)
      c.kernel_root, c.kernel_root_src = root, root_src

      if root then
        local vm = root .. "/vmlinux"
        if vim.uv.fs_stat(vm) then
          c.vmlinux, c.vmlinux_src = vm, root_src
        end
      end
      if not c.vmlinux and inst.kernel_image then
        local up = D.vmlinux_upward(vim.fs.dirname(inst.kernel_image))
        if up then
          c.vmlinux, c.vmlinux_src = up, "found by walking up from the qemu -kernel path"
          c.kernel_root = c.kernel_root or vim.fs.dirname(up)
        end
      end
      if not c.vmlinux and inst.kernel_image and D.elf_arch(inst.kernel_image) then
        c.vmlinux = inst.kernel_image
        c.vmlinux_src = "qemu -kernel is an ELF, used as the symbol file"
        c.kernel_root = c.kernel_root or vim.fs.dirname(inst.kernel_image)
        c.bare_metal = true
      end

      if c.vmlinux then
        c.arch, c.arch_src = D.elf_arch(c.vmlinux), "e_machine field of the symbol file"
      end
      if not c.arch then
        c.arch, c.arch_src = inst.qemu_arch, "qemu binary name"
      elseif inst.qemu_arch and inst.qemu_arch ~= c.arch then
        local pair = { aarch64 = "aarch64", x86_64 = "x86_64", riscv64 = "riscv64", arm = "arm" }
        if pair[inst.qemu_arch] ~= c.arch then
          c.notes[#c.notes + 1] = ("architecture mismatch: qemu=%s symbols=%s"):format(inst.qemu_arch, c.arch)
        end
      end

      if inst.gdb_port then
        c.target = "localhost:" .. inst.gdb_port
        c.target_src = ("-gdb %s of qemu pid %d"):format(inst.gdb_dev, inst.pid)
        c.listening = listen[inst.gdb_port] == true
        c.busy = established[inst.gdb_port] == true
        if not c.listening then
          c.notes[#c.notes + 1] = "the port is not in LISTEN state"
        end
        if c.busy then
          c.notes[#c.notes + 1] = "a client is already attached (the gdbstub accepts only one)"
        end
      else
        c.target = inst.gdb_other
        c.target_src = ("-gdb %s of qemu pid %d"):format(inst.gdb_other, inst.pid)
      end

      c.kaslr = D.kaslr(inst, c.kernel_root)
      c.frozen = inst.frozen
      if not c.vmlinux then
        c.notes[#c.notes + 1] = "no symbol file found, enter one manually"
      end
      out[#out + 1] = c
    end
  end
  return out
end

function M.describe(c)
  return ("%s  %s  pid %d  %s  KASLR %s%s"):format(
    pad(c.arch or "?", 8),
    pad(c.target or "?", 18),
    c.qemu and c.qemu.pid or 0,
    c.frozen and "frozen (-S)" or "running",
    c.kaslr and c.kaslr.state or "unknown",
    c.busy and "  [busy]" or (c.vmlinux and "" or "  [no symbols]")
  )
end

function M.report()
  local cands = M.candidates()
  local lines = {}
  if #cands == 0 then
    lines[#lines + 1] = "No qemu-system-* process is exposing a gdbstub."
    lines[#lines + 1] = "Start a guest first, e.g. with run-qemu.sh."
  end
  for i, c in ipairs(cands) do
    lines[#lines + 1] = ("[%d] %s  pid %d"):format(i, c.qemu.exe, c.qemu.pid)
    local rows = {
      { "target", c.target, c.target_src },
      { "symbols", short(c.vmlinux), c.vmlinux_src },
      { "arch", c.arch, c.arch_src },
      { "kaslr", c.kaslr and c.kaslr.state, c.kaslr and c.kaslr.source },
      { "state", c.frozen and "frozen at the reset vector (-S)" or "already running", "qemu command line" },
      { "machine", c.qemu.machine, "qemu command line" },
      { "port", c.listening and (c.busy and "LISTEN, busy" or "LISTEN, free") or "not observed", "/proc/net/tcp" },
    }
    for _, r in ipairs(rows) do
      local value = tostring(r[2] or "-")
      if vim.fn.strdisplaywidth(value) > 46 then
        lines[#lines + 1] = ("    %s%s"):format(pad(r[1], 12), value)
        if r[3] then
          lines[#lines + 1] = ("    %s<- %s"):format(pad("", 12), r[3])
        end
      else
        lines[#lines + 1] = ("    %s%s%s"):format(pad(r[1], 12), pad(value, 46), r[3] and ("<- " .. r[3]) or "")
      end
    end
    for _, n in ipairs(c.notes) do
      lines[#lines + 1] = "    warning     " .. n
    end
    lines[#lines + 1] = ""
  end
  return lines
end

function M.show_report()
  local lines = M.report()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local width = math.min(vim.o.columns - 4, 110)
  local height = math.min(vim.o.lines - 6, math.max(#lines, 3))
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " QEMU debug targets found on this host ",
  })
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
end

local function build(c)
  local arch = c.arch or "x86_64"
  return {
    name = ("kernel %s @ %s"):format(arch, c.target),
    type = "gdb_kernel",
    request = "attach",
    program = c.vmlinux,
    target = c.target,
    gdb_bin = D.gdb_for(arch),
    kernel_root = c.kernel_root,
    kgdb_auto = c.kgdb_auto and true or false,
    arch = arch,
  }
end

function M.manual(cb)
  vim.ui.input({ prompt = "Symbol file (vmlinux or ELF): ", completion = "file", default = "" }, function(vm)
    if not vm or vm == "" then
      return
    end
    vm = vim.fn.fnamemodify(vim.fn.expand(vm), ":p")
    if not vim.uv.fs_stat(vm) then
      vim.notify("No such file: " .. vm, vim.log.levels.ERROR)
      return
    end
    vim.ui.input({ prompt = "Target (host:port or /dev/pts/N): ", default = "localhost:1234" }, function(t)
      if not t or t == "" then
        return
      end
      local arch = D.elf_arch(vm)
      cb(build({
        vmlinux = vm,
        target = t,
        arch = arch,
        kernel_root = vim.fs.dirname(vm),
        kaslr = { state = "unknown", source = "entered manually" },
      }))
    end)
  end)
end

-- Mirrors what run-gdb.sh does on connect, stopping one step earlier.  The
-- order matters: the tool cannot calibrate the phys<->virt offset until
-- `bootbreak` has walked past the reset vector to the kernel entry.  It stops
-- there, on the first head.S instruction with the MMU still off, because that is
-- where reading the boot assembly starts.  `kearly kaslr auto` would run on to
-- the MMU crossing and park on the branch into the high map, which makes the
-- first step jump straight into virtual addresses; type it in the gdb console
-- when that is what you want.  A breakpoint set while the slide is still unknown
-- arms a catcher on the crossing by itself, so symbols still line up.
function M.arm_kaslr(session)
  local cfg = session and session.config or {}
  if not cfg.kgdb_auto then
    return
  end
  local notify = require("dbg.notify")
  local gdbq = require("dbg.gdbq")
  local caps = require("dbg.caps")

  caps.detect(session, function(c)
    if not (c and c.commands and c.commands.kearly) then
      notify.warn("This target has no `kearly`; early-boot symbols are not available")
      return
    end
    local steps = { "kearly on", "kearly bootbreak", "kearly status" }

    local index = 0
    local function next_step()
      index = index + 1
      local cmd = steps[index]
      if not cmd then
        vim.schedule(function()
          pcall(function()
            require("dbg.registers").render()
            require("dbg.session").probe()
            require("dbg.layout").resize()
          end)
        end)
        return
      end
      gdbq.run(cmd, function(out)
        local text = vim.trim(tostring(out or ""))
        if cmd == "kearly status" then
          local offset = text:match("offset%(PA%-VA%)=(%S+)")
          local enabled = text:match("enabled=(%S+)")
          notify.info(("kearly: enabled=%s offset=%s"):format(tostring(enabled), tostring(offset)))
        elseif text:find("[Ee]rror") or text:find("Undefined") then
          notify.warn(cmd .. ": " .. (text:match("[^\n]+") or text))
        end
        vim.defer_fn(next_step, 200)
      end)
    end
    notify.info("Arming the early-boot symbolizer")
    next_step()
  end)
end

-- A gdbstub that goes away takes the session with it, but nothing tells the
-- client: requests simply stop being answered.  Watch the QEMU process we
-- attached to and close the session with a reason when it disappears.
local watchdog = nil

function M.stop_watchdog()
  if watchdog then
    pcall(function()
      watchdog:stop()
      watchdog:close()
    end)
    watchdog = nil
  end
end

function M.watch_target(session)
  M.stop_watchdog()
  local pid = session and (session.config or {}).qemu_pid
  if not pid then
    return
  end
  local timer = vim.uv.new_timer()
  watchdog = timer
  timer:start(
    2000,
    2000,
    vim.schedule_wrap(function()
      local dap = require("dap")
      if dap.session() ~= session then
        M.stop_watchdog()
        return
      end
      if vim.uv.fs_stat("/proc/" .. tostring(pid)) then
        return
      end
      M.stop_watchdog()
      require("dbg.notify").error(("The QEMU process (pid %s) is gone; the gdbstub died with it"):format(pid))
      pcall(function()
        dap.disconnect({ terminateDebuggee = false })
      end)
      vim.defer_fn(function()
        if require("dap").session() then
          pcall(function()
            require("dap").close()
          end)
        end
        pcall(function()
          require("dbg.layout").leave()
        end)
      end, 1200)
    end)
  )
end

function M.start(opts)
  opts = opts or {}
  local items = {}
  for _, c in ipairs(M.candidates()) do
    items[#items + 1] = c
  end
  items[#items + 1] = "manual"

  vim.ui.select(items, {
    prompt = "Kernel debug target",
    format_item = function(item)
      if item == "manual" then
        return "enter a symbol file and target by hand"
      end
      return M.describe(item)
    end,
  }, function(choice)
    if not choice then
      return
    end
    -- Two ways in, offered together rather than hidden behind two commands:
    -- attach where the kernel already is, or arm the early-boot machinery and
    -- stop on the first head.S instruction.  `kaslr_auto` only tells the adapter
    -- to put KGDB_X86_KASLR in gdb's environment, which x86 needs to find the
    -- decompressor-relocated kernel and which a console command cannot set.
    local function launch(cfg, early)
      cfg.kgdb_auto = early and true or false
      local kaslr = cfg.kaslr_state
      if early and kaslr and kaslr ~= "off" then
        cfg.kaslr_auto = true
      else
        cfg.kaslr_auto = nil
      end
      if not early and kaslr == "unknown" then
        require("dbg.notify").warn("KASLR state is unknown here; if symbols do not line up, attach in early-boot mode")
      end
      require("dap").run(cfg)
    end

    local function run(cfg)
      if opts.kgdb_auto ~= nil then
        launch(cfg, opts.kgdb_auto)
        return
      end
      local kaslr = cfg.kaslr_state or "unknown"
      local modes = {
        { early = false, label = "Attach now — wherever the kernel has got to" },
        {
          early = true,
          label = "Early boot — stop on the first head.S instruction, MMU still off"
            .. (kaslr ~= "off" and (", KASLR " .. kaslr) or ""),
        },
      }
      vim.ui.select(modes, {
        prompt = "How to attach",
        format_item = function(m)
          return m.label
        end,
      }, function(mode)
        if mode then
          launch(cfg, mode.early)
        end
      end)
    end
    if choice == "manual" then
      M.manual(run)
      return
    end
    if not choice.vmlinux then
      vim.notify("No symbol file was found for this target, falling back to manual entry.", vim.log.levels.WARN)
      M.manual(run)
      return
    end
    if choice.busy then
      vim.notify("This gdbstub already has a client attached; detach it first.", vim.log.levels.ERROR)
      return
    end
    local cfg = build(choice)
    cfg.qemu_pid = choice.pid
    cfg.kaslr_state = choice.kaslr and choice.kaslr.state or "unknown"
    cfg.kaslr_source = choice.kaslr and choice.kaslr.source or nil
    -- The early-boot symbolizer calibrates the phys<->virt offset at runtime,
    -- so it copes with KASLR on its own; relocating gdb's symbols to the slide
    -- is a separate step the tool only takes when asked.  Ask for it here
    -- rather than leaving a note telling you to type it.
    run(cfg)
  end)
end

return M
