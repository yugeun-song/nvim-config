-- Everything here speaks QEMU's human monitor through the gdbstub's `monitor`
-- passthrough: gpa2hva, gva2gpa, xp, cpu. None of it exists on a target that is
-- not a QEMU guest -- kgdb over a serial line has no monitor to ask -- so the
-- guard reports "unknown" there rather than pretending to know.
local M = {}

M.mode = "auto"

local cache = {}
local ncpu = nil
local monitor_ok = nil

local function page_of(hex)
  local s = hex:gsub("^0[xX]", "")
  s = string.rep("0", math.max(0, 16 - #s)) .. s
  local hi = tonumber(s:sub(1, 8), 16) or 0
  local lo = (tonumber(s:sub(9, 16), 16) or 0)
  lo = lo - (lo % 4096)
  return string.format("0x%08x%08x", hi, lo)
end

function M.invalidate()
  cache = {}
  ncpu = nil
end

function M.active(session)
  if M.mode == "off" then
    return false
  end
  if M.mode == "on" then
    return true
  end
  local cfg = session and session.config or {}
  return cfg.type == "gdb_kernel"
end

local function monitor(session, cmd, cb)
  local frame = session.current_frame
  session:request(
    "evaluate",
    { expression = "monitor " .. cmd, context = "repl", frameId = frame and frame.id },
    function(err, res)
      if err then
        cb(nil)
        return
      end
      cb(tostring((res or {}).result or ""))
    end
  )
end

-- gva2gpa translates through whichever core QEMU's monitor is pointed at, state
-- shared with everything else on this gdbstub.  Pin it to the core gdb stopped
-- on: a monitor left on a parked secondary answers Unmapped for every kernel VA.
-- `idx` names a core explicitly (the sweep below); nil means the core gdb stopped
-- on, worked out by gdb itself so this side never has to map a thread id to a cpu.
local function pin_cpu(session, idx, cb)
  local expr = idx and ("monitor cpu " .. idx) or 'eval "monitor cpu %d", $_thread > 0 ? $_thread - 1 : 0'
  local frame = session.current_frame
  session:request("evaluate", {
    expression = expr,
    context = "repl",
    frameId = frame and frame.id,
  }, function()
    cb()
  end)
end

-- How many cores this guest has, asked of the guest.  Only the sweep needs it, so
-- it is paid for only where one happens, and it is dropped at every stop with the
-- rest of the cache rather than carried into the next session.
local function cpu_count(session, cb)
  if ncpu then
    cb(ncpu)
    return
  end
  monitor(session, "info cpus", function(out)
    local n = 0
    for _ in tostring(out or ""):gmatch("CPU #%d+") do
      n = n + 1
    end
    ncpu = (n > 0) and n or 1
    cb(ncpu)
  end)
end

function M.qemu_check(session, addr, cb)
  if not M.active(session) then
    cb("ram", "guard disabled")
    return
  end
  local page = page_of(addr)
  local hit = cache[page]
  if hit then
    cb(hit[1], hit[2])
    return
  end

  -- The monitor's current core is state shared with everything else on this
  -- gdbstub -- the sysreg reads, anything the user types -- so a sweep that ended
  -- on some other core would answer for it from then on.  Whatever the verdict,
  -- and on every path out, it goes back to the core gdb is stopped on first.
  local moved = false
  local function finish(verdict, why)
    cache[page] = { verdict, why }
    if not moved then
      cb(verdict, why)
      return
    end
    moved = false
    pin_cpu(session, nil, function()
      cb(verdict, why)
    end)
  end

  -- `gpa2hva` is the decisive question and the only one: RAM can be read the
  -- ordinary way, a device region must never be touched, and "No memory is mapped"
  -- means the gpa we were handed was not a translation at all.  Only that last
  -- answer is worth putting to another core, which is what `undecided` is for.
  local function check_gpa(gpa, via, undecided)
    monitor(session, "gpa2hva " .. gpa, function(out)
      if not out or out == "" then
        monitor_ok = false
        finish("unknown", "no reply from monitor gpa2hva")
        return
      end
      monitor_ok = true
      if out:find("is not RAM") then
        finish("device", "gpa " .. gpa .. " is a device region (" .. via .. ")")
      elseif out:find("No memory is mapped") then
        if undecided then
          undecided()
        else
          finish("unmapped", "no memory mapped at gpa " .. gpa .. " (" .. via .. ")")
        end
      elseif out:find("Host virtual address") or out:find("is 0x") then
        finish("ram", "gpa " .. gpa .. " is RAM (" .. via .. ")")
      else
        finish("unknown", "unparsed gpa2hva reply (" .. via .. ")")
      end
    end)
  end

  -- Nothing translated the page anywhere, so it is not a live VA on this guest at
  -- all.  Read it for what it then is -- a physical address -- which is what an
  -- MMU-off stop hands us in the first place.
  local function as_physical(why)
    monitor(session, "gpa2hva " .. page, function(phys)
      if phys and phys:find("Host virtual address") then
        finish("phys_ram", why .. ", but " .. page .. " is RAM as a physical address")
      elseif phys and phys:find("is not RAM") then
        finish("device", why .. ", and " .. page .. " is a device region as a physical address")
      else
        finish("unmapped", why .. " and it is no physical RAM either")
      end
    end)
  end

  -- One core's page tables are not the guest's.  Stop a v4.6 arm64 guest at
  -- `__enable_mmu` and continue and the second stop is the SECONDARY core, still
  -- MMU-off in head.S while the primary already runs the kernel: ask that core to
  -- translate a kernel VA and arm64's gva2gpa answers a flat `Unmapped`, because
  -- that core has no translation on -- measured, cpu 1 `Unmapped` and cpu 0
  -- `gpa: 0x40082c00` for the same address in the same stop.  Taking the parked
  -- core's word for it refused every kernel pointer in the machine as unmapped,
  -- with the memory the user asked for sitting in RAM the whole time.  So ask the
  -- core gdb is on first -- it is the one whose regime the read will use, when it
  -- has one -- and only where it cannot answer, ask the others.  The monitor's
  -- current core is shared state, so it goes back to the selected one either way.
  local function sweep(i, n)
    if i > n then
      as_physical("no core translates " .. page)
      return
    end
    -- Round 0 is the core gdb stopped on, named by gdb rather than by index; the
    -- rest are cpu 0..n-1.  Written out rather than as `(i == 0) and nil or i - 1`,
    -- which in Lua is `nil or i - 1` and so is never nil -- it pinned `cpu -1`.
    local idx
    if i > 0 then
      idx = i - 1
      moved = true
    end
    pin_cpu(session, idx, function()
      monitor(session, "gva2gpa " .. page, function(out)
        local nxt = function()
          sweep(i + 1, n)
        end
        if not out or out == "" then
          -- No gva2gpa at all (a qemu too old, or no monitor): one answer for the
          -- whole guest, so do not walk the cores asking it again.
          as_physical("monitor gva2gpa unavailable")
          return
        end
        local gpa = out:match("gpa:%s*(0x%x+)")
        if gpa then
          local via = (idx and ("cpu " .. idx) or "the stopped core")
          check_gpa(gpa, "translated by gva2gpa on " .. via, nxt)
          return
        end
        nxt() -- `Unmapped`, or a reply this does not parse: try the next core
      end)
    end)
  end

  cpu_count(session, function(n)
    sweep(0, n)
  end)
end

function M.qemu_read_phys(session, addr, count, cb)
  local frame = session.current_frame
  session:request(
    "evaluate",
    { expression = ("monitor xp/%dxb %s"):format(count, addr), context = "repl", frameId = frame and frame.id },
    function(err, res)
      if err then
        cb(nil, err.message or "monitor xp failed")
        return
      end
      local bytes = {}
      for b in tostring((res or {}).result or ""):gmatch("0x(%x%x)%f[%W]") do
        bytes[#bytes + 1] = string.char(tonumber(b, 16))
      end
      if #bytes == 0 then
        cb(nil, "monitor xp returned no bytes")
        return
      end
      cb(table.concat(bytes))
    end
  )
end

function M.explain(verdict, why)
  local label = {
    ram = "RAM",
    phys_ram = "physical RAM",
    device = "device region",
    unmapped = "not mapped",
    unknown = "undecided",
  }
  return (label[verdict] or verdict) .. " — " .. tostring(why)
end

return M
