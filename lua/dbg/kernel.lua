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
      if not c.vmlinux then
        -- Booted through firmware: no -kernel to derive anything from.
        local best, best_src, best_dist, best_arch
        for _, path in ipairs(D.qemu_paths(inst)) do
          local vm, dist = D.vmlinux_near(path)
          if vm then
            local arch = D.elf_arch(vm)
            local better = not best
              or dist < best_dist
              or (dist == best_dist and arch == inst.qemu_arch and best_arch ~= inst.qemu_arch)
            if better then
              best, best_dist, best_arch = vm, dist, arch
              best_src = "found beside " .. path .. " on the qemu command line, which carries no -kernel"
            end
          end
        end
        if best then
          c.vmlinux, c.vmlinux_src = best, best_src
          c.kernel_root = c.kernel_root or vim.fs.dirname(best)
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
        -- The host the stub was bound to (-gdb tcp:HOST:PORT). A specific bind
        -- must be honoured, or the guest shows as listening but connects from nowhere.
        local ghost = tostring(inst.gdb_dev or ""):match("^tcp:(.*):%d+$")
        if not ghost or ghost == "" or ghost == "0.0.0.0" or ghost == "::" or ghost == "[::]" then
          ghost = "localhost"
        end
        c.target = ghost .. ":" .. inst.gdb_port
        c.target_src = ("-gdb %s of qemu pid %d"):format(inst.gdb_dev, inst.pid)
        c.listening = listen[inst.gdb_port] == true
        -- Attached means qemu owns an established socket, not that one exists: a
        -- second client shows as ESTABLISHED while queued. An unreadable fd table
        -- (another uid) stays unknown, as in kbuildlab's CLI.
        local owned = D.socket_inodes(inst.pid)
        local rows = established[inst.gdb_port] or {}
        if owned == nil then
          c.busy, c.busy_src = nil, "qemu's fd table is unreadable"
        else
          local mine, queued = 0, 0
          for _, ino in ipairs(rows) do
            if owned[ino] then
              mine = mine + 1
            else
              queued = queued + 1
            end
          end
          c.busy = mine > 0
          c.queued = queued
          c.busy_src = ("%d owned / %d queued established socket(s)"):format(mine, queued)
        end
        if not c.listening then
          c.notes[#c.notes + 1] = "the port is not in LISTEN state"
        end
        if c.busy then
          c.notes[#c.notes + 1] = "a client is already attached (the gdbstub serves one; "
            .. "this session would wait in the accept queue)"
        elseif c.busy == nil then
          c.notes[#c.notes + 1] = "cannot tell whether a debugger is attached " .. "(" .. (c.busy_src or "?") .. ")"
        elseif (c.queued or 0) > 0 then
          c.notes[#c.notes + 1] = ("%d client(s) queued on the stub but none accepted yet"):format(c.queued)
        end
      else
        c.target = inst.gdb_other
        c.target_src = ("-gdb %s of qemu pid %d"):format(inst.gdb_other, inst.pid)
      end

      c.kaslr = D.kaslr(inst, c.kernel_root)
      -- A firmware chain has no -append to read KASLR from; use what the
      -- launcher recorded for this port.
      c.run_state = D.run_state(inst.gdb_port, inst.pid)
      if c.run_state and c.run_state.KBL_KASLR then
        local on = c.run_state.KBL_KASLR
        c.kaslr = {
          state = (on == "1" or on == "on" or on == "yes") and "on" or "off",
          source = "KBL_KASLR in " .. c.run_state.path .. ", recorded when this port was started",
        }
      end
      c.frozen = inst.frozen

      -- Last resort, and the one a firmware chain needs: no -kernel, so the
      -- recorded KBL_TREE is the only way to <src>/vmlinux, as in kbuildlab.
      if not c.vmlinux and c.run_state and c.run_state.KBL_TREE then
        local tree = c.run_state.KBL_TREE
        local cand = {}
        local sd = D.tree_value(tree, "SRC_DIR")
        if sd and sd ~= "" then
          cand[#cand + 1] = tree .. "/" .. sd .. "/vmlinux"
        end
        cand[#cand + 1] = tree .. "/kernel/vmlinux"
        local dir = vim.uv.fs_scandir(tree)
        while dir do
          local name, kind = vim.uv.fs_scandir_next(dir)
          if not name then
            break
          end
          if kind == "directory" then
            cand[#cand + 1] = tree .. "/" .. name .. "/vmlinux"
          end
        end
        for _, vm in ipairs(cand) do
          if vim.uv.fs_stat(vm) then
            c.vmlinux = vm
            c.vmlinux_src = "KBL_TREE in " .. tostring(c.run_state.path)
            c.kernel_root = c.kernel_root or vim.fs.dirname(vm)
            if not c.arch then
              c.arch, c.arch_src = D.elf_arch(vm), "e_machine field of the symbol file"
            end
            break
          end
        end
      end

      if not c.vmlinux then
        c.notes[#c.notes + 1] = "no symbol file found, enter one manually"
      end
      out[#out + 1] = c
    end
  end
  return out
end

function M.describe(c)
  return ("%s  %s  pid %d  %s  %s  KASLR %s%s"):format(
    pad(c.arch or "?", 8),
    pad(c.target or "?", 18),
    c.qemu and c.qemu.pid or 0,
    c.frozen and "frozen (-S)" or "running",
    pad((c.run_state and c.run_state.KBL_BOOT) or "boot?", 6),
    c.kaslr and c.kaslr.state or "unknown",
    c.busy and "  [attached]"
      or (c.busy == nil and "  [attach state unknown]")
      or ((c.queued or 0) > 0 and ("  [%d queued]"):format(c.queued))
      or (c.vmlinux and "" or "  [no symbols]")
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
      {
        "boot",
        c.run_state and c.run_state.KBL_BOOT,
        c.run_state and ("recorded in " .. c.run_state.path .. " when this port was started"),
      },
      {
        "entry",
        c.run_state and c.run_state.KBL_LOADADDR,
        c.run_state and c.run_state.KBL_LOADADDR and "where the bootloader lands the kernel, from the same file",
      },
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
    -- Carried for a hand-entered target too: nil here reads as "cannot tell",
    -- which the adapter counts as KASLR on.
    run_state = c.run_state,
    kaslr_state = c.kaslr and c.kaslr.state or "unknown",
    kaslr_source = c.kaslr and c.kaslr.source or nil,
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
      local port = tonumber(tostring(t):match(":(%d+)$"))
      -- A typed-in target names a port but no pid, so the run state is read
      -- without the freshness test candidates() applies: a file left by a
      -- previous guest on the same port is believed.
      local rs = port and D.run_state(port) or nil
      local kaslr = { state = "unknown", source = "entered manually" }
      if rs and rs.KBL_KASLR then
        kaslr = {
          state = rs.KBL_KASLR == "1" and "on" or "off",
          source = "KBL_KASLR in " .. tostring(rs.path) .. ", recorded when this port was started",
        }
      end
      cb(build({
        vmlinux = vm,
        target = t,
        arch = arch,
        kernel_root = vim.fs.dirname(vm),
        run_state = rs,
        kaslr = kaslr,
      }))
    end)
  end)
end

-- The u-boot ELF names the firmware stages; its range does not overlap vmlinux,
-- so both resolve. gdb's DAP loads the program only once attach lands, so this
-- runs from the session rather than as a -ex argument.
function M.load_firmware_symbols(session, done)
  done = done or function() end
  local cfg = session and session.config or {}
  -- Re-read the run state, as dap.lua does on connect: a replayed config can
  -- describe a guest since restarted in another boot mode.
  local port = tonumber(tostring(cfg.target or ""):match(":(%d+)$"))
  local qpid = cfg.qemu and cfg.qemu.pid or nil
  local state = (port and D.run_state(port, qpid)) or cfg.run_state
  if not (state and state.KBL_BOOT == "uboot" and cfg.kernel_root) then
    return done()
  end
  local rel, dir = require("dbg.discover").tree_value(cfg.kernel_root, "UBOOT")
  if not (rel and rel ~= "" and dir) then
    return done()
  end
  local path = rel:match("^/") and rel or (dir .. "/" .. rel)
  local elf = (path:gsub("%.bin$", ""))
  if not vim.uv.fs_stat(elf) then
    return done()
  end
  require("dbg.gdbq").run("add-symbol-file " .. elf .. " -o 0", function()
    done()
  end)
end

-- Mirrors run-gdb.sh's connect sequence, stopping one step earlier: park on
-- the first head.S instruction with the MMU off. `kearly kaslr auto` would run
-- on to the MMU crossing; type it in the console when wanted. A breakpoint set
-- before the slide is known arms its own catcher on the crossing.
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

-- A dying gdbstub tells the client nothing; watch the QEMU pid instead.
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
  local timer = assert(vim.uv.new_timer())
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
      -- Close the session, not the windows: what the guest printed stays readable.
      vim.defer_fn(function()
        if require("dap").session() then
          pcall(function()
            require("dap").close()
          end)
        end
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
    -- Attach where the kernel is, or arm early boot and stop on the first head.S
    -- instruction. GDBTOOLS_X86_KASLR is not decided here: KASLR is a fact about
    -- the guest, and the adapter reads it from the recorded run and kaslr_state.
    local function launch(cfg, early)
      cfg.kgdb_auto = early and true or false
      local kaslr = cfg.kaslr_state
      if not early and kaslr == "unknown" then
        require("dbg.notify").warn("KASLR state is unknown here; if symbols do not line up, attach in early-boot mode")
      elseif not early and kaslr == "on" then
        -- Under KASLR nothing lines up until the slide is measured.
        require("dbg.notify").warn(
          "This guest booted with KASLR on. vmlinux symbols are at their link addresses until the slide "
            .. "is measured: run `kearly on` then `kearly calibrate <symbol>` in the gdb console, or attach in early-boot mode."
        )
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
    -- The watchdog needs the qemu pid, which only a discovered target has.
    cfg.qemu_pid = choice.qemu and choice.qemu.pid or nil
    -- The early-boot symbolizer copes with KASLR itself; relocating gdb's
    -- symbols to the slide is a separate step, so ask for it here.
    run(cfg)
  end)
end

return M
