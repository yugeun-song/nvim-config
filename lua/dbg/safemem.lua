local M = {}

M.mode = "auto"

local cache = {}
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

-- gva2gpa translates through the core QEMU's monitor happens to be pointed at,
-- which is state shared with everything else on this gdbstub.  Point it at the
-- core gdb is stopped on before asking, instead of inheriting whatever is there:
-- a monitor left on a parked secondary answers Unmapped for every live kernel VA.
local function pin_cpu(session, cb)
  local frame = session.current_frame
  session:request("evaluate", {
    expression = 'eval "monitor cpu %d", $_thread > 0 ? $_thread - 1 : 0',
    context = "repl",
    frameId = frame and frame.id,
  }, function()
    cb()
  end)
end

function M.check(session, addr, cb)
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

  local function finish(verdict, why)
    cache[page] = { verdict, why }
    cb(verdict, why)
  end

  local function check_gpa(gpa, via)
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
        finish("unmapped", "no memory mapped at gpa " .. gpa .. " (" .. via .. ")")
      elseif out:find("Host virtual address") or out:find("is 0x") then
        finish("ram", "gpa " .. gpa .. " is RAM (" .. via .. ")")
      else
        finish("unknown", "unparsed gpa2hva reply (" .. via .. ")")
      end
    end)
  end

  pin_cpu(session, function()
    monitor(session, "gva2gpa " .. page, function(out)
      if not out or out == "" then
        check_gpa(page, "monitor gva2gpa unavailable, treated as physical")
        return
      end
      local gpa = out:match("gpa:%s*(0x%x+)")
      if gpa then
        check_gpa(gpa, "translated by gva2gpa")
        return
      end
      if out:find("Unmapped") then
        monitor(session, "gpa2hva " .. page, function(phys)
          if phys and phys:find("Host virtual address") then
            finish("phys_ram", "not a live VA, but " .. page .. " is RAM as a physical address")
          elseif phys and phys:find("is not RAM") then
            finish("device", "not a live VA, and " .. page .. " is a device region as a physical address")
          else
            finish("unmapped", "gva2gpa reported Unmapped and it is no physical RAM either")
          end
        end)
        return
      end
      check_gpa(page, "unparsed gva2gpa reply, treated as physical")
    end)
  end)
end

function M.read_phys(session, addr, count, cb)
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
