-- QEMU human-monitor queries (gpa2hva, gva2gpa, xp, cpu) through the gdbstub's
-- `monitor` passthrough. A non-QEMU target has no monitor, so the guard answers
-- "unknown" there.
local M = {}

M.mode = "auto"

local cache = {}
local ncpu = nil

-- Addresses are carried as 32-bit halves, not as Lua numbers: a kernel VA such as
-- 0xffffff8008000000 is past 2^53 and would not survive one.
local function split(hex)
  local s = hex:gsub("^0[xX]", "")
  s = string.rep("0", math.max(0, 16 - #s)) .. s
  return tonumber(s:sub(1, 8), 16) or 0, tonumber(s:sub(9, 16), 16) or 0
end

local function join(hi, lo)
  return string.format("0x%08x%08x", hi, lo)
end

local function page_of(hex)
  local hi, lo = split(hex)
  return join(hi, lo - (lo % 4096))
end

-- Every page a read of `count` bytes from `hex` touches, first one first.
local function pages_of(hex, count)
  local hi, lo = split(hex)
  local base = lo - (lo % 4096)
  local crossings = math.floor(((lo % 4096) + math.max(count, 1) - 1) / 4096)
  local out = { join(hi, base) }
  for k = 1, crossings do
    local h, l = hi, base + k * 4096
    if l > 0xffffffff then
      h, l = hi + 1, l - 0x100000000
    end
    out[#out + 1] = join(h, l)
  end
  return out
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

-- The monitor translates on whichever core it is pointed at, shared state on this
-- gdbstub; a parked secondary answers Unmapped for every kernel VA. `idx` names a
-- core, nil is the core gdb stopped on.
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

-- Asked only for a sweep; dropped with the cache at every stop.
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

  -- The monitor core is shared state, so every path out first returns it to the
  -- core gdb stopped on.
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

  -- gpa2hva decides: RAM reads normally, a device is never touched, and "No memory
  -- is mapped" means the gpa was no translation, the one answer worth putting to
  -- another core (`undecided`).
  local function check_gpa(gpa, via, undecided)
    monitor(session, "gpa2hva " .. gpa, function(out)
      if not out or out == "" then
        finish("unknown", "no reply from monitor gpa2hva")
        return
      end
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

  -- No core translates the page, so it is read as a physical address, which is
  -- what an MMU-off stop hands over.
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

  -- The core gdb stopped on first, then cpu 0..n-1. One core's page tables are not
  -- the guest's: a secondary still MMU-off in head.S (arm64 v4.6 after
  -- `__enable_mmu`) answers Unmapped for a VA the primary translates.
  local function sweep(i, n)
    if i > n then
      as_physical("no core translates " .. page)
      return
    end
    -- `(i == 0) and nil or i - 1` is never nil in Lua; it pinned cpu -1.
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
          -- No gva2gpa (old qemu, or no monitor) is one answer for the whole guest.
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

-- A window runs to 8 KiB and can cross into a device page after the first. The
-- first page decides how the window is read; the pages after it can only veto.
function M.qemu_check_range(session, addr, count, cb)
  local pages = pages_of(addr, count or 1)
  M.qemu_check(session, pages[1], function(verdict, why)
    if verdict ~= "ram" and verdict ~= "phys_ram" or #pages == 1 then
      cb(verdict, why)
      return
    end
    local i = 1
    local function step()
      i = i + 1
      if i > #pages then
        cb(verdict, why)
        return
      end
      M.qemu_check(session, pages[i], function(v, w)
        if v == "device" then
          cb("device", ("%s -- page %d of the %d this read covers"):format(w, i, #pages))
        else
          step()
        end
      end)
    end
    step()
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
