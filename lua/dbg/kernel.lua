local D = require("dbg.discover")
local notify = require("dbg.notify")

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

-- Live guests, as kbuildlab sees them: kbuildlab started them, records their
-- tree and boot, and owns every rule about them.  cb(list) or cb(nil, why).
function M.candidates(cb)
  D.kbuildlab_json({ "attach", "--list", "--json" }, nil, function(rows, why)
    if not rows then
      return cb(nil, why)
    end
    for _, c in ipairs(rows) do
      c.busy = c.dbg and c.dbg:match("^attached") ~= nil
    end
    cb(rows)
  end)
end

function M.describe(c)
  return ("%s  %s  pid %d  %s  %s  KASLR %s%s"):format(
    pad(c.name or "?", 16),
    pad(c.target or "?", 18),
    c.pid or 0,
    c.frozen and "frozen (-S)" or "running",
    pad(c.boot or "boot?", 6),
    c.kaslr == true and "on" or (c.kaslr == false and "off" or "unknown"),
    c.busy and "  [attached]"
      or (c.dbg == "unknown" and "  [attach state unknown]")
      or (c.dbg == "waiting" and "  [a client is queued]")
      or (not c.tree and "  [no tree recorded]")
      or ""
  )
end

function M.report(cb)
  M.candidates(function(cands, why)
    local lines = {}
    if not cands then
      lines[#lines + 1] = why
    elseif #cands == 0 then
      lines[#lines + 1] = "No guest is running.  Start one: kbuildlab run TREE"
    end
    for i, c in ipairs(cands or {}) do
      lines[#lines + 1] = ("[%d] %s  %s  pid %d"):format(i, c.name or "?", c.qbin or "qemu", c.pid or 0)
      local rows = {
        { "target", c.target },
        { "tree", short(c.tree) },
        { "state", c.frozen and "frozen at the reset vector (-S)" or "already running" },
        { "boot", c.boot },
        { "kaslr", c.kaslr == true and "on" or (c.kaslr == false and "off" or "unknown") },
        { "ssh", c.ssh and ("localhost:" .. c.ssh) or "-" },
        { "debugger", c.dbg or "-" },
      }
      for _, r in ipairs(rows) do
        lines[#lines + 1] = ("    %s%s"):format(pad(r[1], 12), tostring(r[2] or "-"))
      end
      lines[#lines + 1] = ""
    end
    cb(lines)
  end)
end

function M.show_report()
  M.report(function(lines)
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
      title = " kbuildlab guests ",
    })
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
  end)
end

-- The DAP configuration names a tree and a port and nothing else: the adapter
-- asks kbuildlab for the session each time it starts, so a replayed
-- configuration follows a guest that was restarted in another boot mode.
local function build(c)
  return {
    name = ("kernel %s @ %s"):format(c.name or "?", c.target or tostring(c.port)),
    type = "gdb_kernel",
    request = "attach",
    target = c.target,
    kbl = { tree = c.name or c.tree, port = c.port },
    kaslr_state = c.kaslr == true and "on" or (c.kaslr == false and "off" or "unknown"),
  }
end

-- A guest kbuildlab did not start: name the registered tree it runs and the
-- port its gdbstub listens on, and kbuildlab describes it from the tree.
function M.manual(cb, port)
  D.kbuildlab_json({ "trees", "--json" }, nil, function(trees, why)
    if not trees then
      return notify.error(why)
    end
    if #trees == 0 then
      return notify.error("No tree is registered: kbuildlab add DIR, or kbuildlab init NAME --arch ARCH")
    end
    vim.ui.select(trees, {
      prompt = "Which tree does the guest run?",
      format_item = function(t)
        return ("%s  %s  %s"):format(pad(t.name, 16), pad(t.arch or "?", 8), t.release or t.version or "")
      end,
    }, function(t)
      if not t then
        return
      end
      vim.ui.input({ prompt = "gdbstub port: ", default = tostring(port or t.gdb_port or "") }, function(p)
        p = tonumber(p)
        if not p then
          return
        end
        cb(build({ name = t.name, tree = t.name, port = p, target = "localhost:" .. p }))
      end)
    end)
  end)
end

-- The u-boot ELF names the firmware stages; its range does not overlap vmlinux,
-- so both resolve. gdb's DAP loads the program only once attach lands, so this
-- runs from the session rather than as a -ex argument.
function M.load_firmware_symbols(session, done)
  done = done or function() end
  local cfg = session and session.config or {}
  if not (cfg.boot == "uboot" and cfg.fwsym and vim.uv.fs_stat(cfg.fwsym)) then
    return done()
  end
  require("dbg.gdbq").run("add-symbol-file " .. cfg.fwsym .. " -o 0", function()
    session.dbg_firmware_symbols = cfg.fwsym
    done()
  end, { session = session })
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
  local gdbq = require("dbg.gdbq")
  local caps = require("dbg.caps")

  caps.detect(session, function(c)
    if not (c and c.commands and c.commands.kearly) then
      notify.warn("This target has no `kearly`; early-boot symbols are not available")
      return
    end
    local on = { session = session }
    local function status()
      gdbq.run("kearly status", function(out)
        local text = vim.trim(tostring(out or ""))
        local offset = text:match("offset%(PA%-VA%)=(%S+)")
        local enabled = text:match("enabled=(%S+)")
        notify.info(("kearly: enabled=%s offset=%s"):format(tostring(enabled), tostring(offset)))
      end, on)
    end

    -- `arm` only plants the entry breakpoint: a bare bootbreak resumes inside the
    -- evaluate, and gdb answers nothing else until the guest stops. It plants none
    -- when the MMU is already on, which the temporary-breakpoint count tells.
    local count = "python print(sum(1 for b in gdb.breakpoints() if b.temporary))"
    local steps = { "kearly on", count, "kearly bootbreak arm", count }
    local outs = {}
    local index = 0
    local function next_step()
      index = index + 1
      local cmd = steps[index]
      if not cmd then
        if (tonumber(outs[4]) or 0) <= (tonumber(outs[2]) or 0) then
          status()
          pcall(function()
            require("dbg.registers").render()
            require("dbg.session").probe()
          end)
          return
        end
        local dap = require("dap")
        local key = "dbg_kearly_" .. tostring(session.id)
        dap.listeners.after.event_stopped[key] = function(s)
          if s == session then
            dap.listeners.after.event_stopped[key] = nil
            -- u-boot is linked at 0, so in the kernel its symbols only rename small
            -- integers; run-gdb.sh drops them at the same point.
            if session.dbg_firmware_symbols then
              session.dbg_firmware_symbols = nil
              gdbq.run("remove-symbol-file -a 0", status, on)
            else
              status()
            end
          end
        end
        dap.set_session(session)
        require("dbg.session").cont()
        return
      end
      gdbq.run(cmd, function(out)
        local text = vim.trim(tostring(out or ""))
        outs[index] = text
        if text:find("[Ee]rror") or text:find("Undefined") then
          notify.warn(cmd .. ": " .. (text:match("[^\n]+") or text))
        end
        vim.schedule(next_step)
      end, on)
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

-- gdb's DAP connects only after configurationDone, so what needs the target
-- waits for the first stop, the attach's.
function M.after_attach(session)
  local dap = require("dap")
  local key = "dbg_kernel_" .. tostring(session.id)
  local function forget()
    dap.listeners.after.event_stopped[key] = nil
    dap.listeners.after.event_terminated[key] = nil
    dap.listeners.after.disconnect[key] = nil
  end
  dap.listeners.after.event_stopped[key] = function(s)
    if s == session then
      forget()
      M.load_firmware_symbols(session, function()
        M.arm_kaslr(session)
      end)
    end
  end
  dap.listeners.after.event_terminated[key] = function(s)
    if s == session then
      forget()
    end
  end
  dap.listeners.after.disconnect[key] = dap.listeners.after.event_terminated[key]
  M.watch_target(session)
end

function M.watch_target(session)
  M.stop_watchdog()
  local cfg = session and session.config or {}
  local pid = cfg.qemu_pid
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
  M.candidates(function(cands, why)
    if not cands then
      notify.error(why)
      return
    end
    local items = {}
    for _, c in ipairs(cands) do
      items[#items + 1] = c
    end
    items[#items + 1] = "manual"

    vim.ui.select(items, {
      prompt = "Kernel debug target",
      format_item = function(item)
        if item == "manual" then
          return "a guest kbuildlab did not start: name its tree and port"
        end
        return M.describe(item)
      end,
    }, function(choice)
      if not choice then
        return
      end
      -- Attach where the kernel is, or arm early boot and stop on the first head.S
      -- instruction.  Everything else -- the gdb, the trust for the kernel's own
      -- scripts, what gdbtools is told -- comes from kbuildlab when the adapter starts.
      local function launch(cfg, early)
        cfg.kgdb_auto = early and true or false
        local kaslr = cfg.kaslr_state
        if not early and kaslr == "unknown" then
          notify.warn("KASLR state is unknown here; if symbols do not line up, attach in early-boot mode")
        elseif not early and kaslr == "on" then
          -- Under KASLR nothing lines up until the slide is measured.
          notify.warn(
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
      if choice.busy then
        notify.error("This gdbstub already has a client attached; detach it first.")
        return
      end
      if not choice.tree then
        M.manual(run, choice.port)
        return
      end
      run(build(choice))
    end)
  end)
end

return M
