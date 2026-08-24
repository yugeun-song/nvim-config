local gdbq = require("dbg.gdbq")

local M = {}

local SYMBOLS = {
  "init_task",
  "linux_banner",
  "_text",
  "_stext",
  "_sdata",
  "init_thread_union",
  "swapper_pg_dir",
  "__libc_start_main",
  "environ",
  "__curbrk",
  "main_arena",
  "main",
}

local COMMANDS = {
  "vmmap",
  "telescope",
  "hexdump",
  "heap",
  "bins",
  "kearly",
  "sym",
  "p2v",
  "mmview",
  "lx-version",
  "lx-dmesg",
  "lx-ps",
  "checksec",
  "piebase",
}

local cache = {}

local function key(session)
  return session and (tostring(session.id or session) .. ":" .. tostring((session.config or {}).name)) or "none"
end

function M.get(session)
  return cache[key(session)]
end

function M.invalidate(session)
  if session then
    cache[key(session)] = nil
  else
    cache = {}
  end
end

-- Each entry answers with a reason when the answer is no, so a feature that is
-- unavailable is refused with an explanation instead of failing somewhere deep.
local FEATURES = {
  line_breakpoints = function(state)
    if state.debug_info == "none" then
      return false, (state.program or "the program") .. " has no debug info; break on a symbol instead"
    end
    if state.debug_info == "external" then
      return true, "debug info is in a separate file"
    end
    return true
  end,
  source_stepping = function(state)
    if state.debug_info == "none" then
      return false, "no line table, stepping is by instruction"
    end
    return true
  end,
  function_breakpoints = function(state)
    if state.adapter.supportsFunctionBreakpoints == false then
      return false, "this adapter does not implement setFunctionBreakpoints"
    end
    return true
  end,
  instruction_breakpoints = function(state)
    if state.adapter.supportsInstructionBreakpoints == false then
      return false, "this adapter does not implement setInstructionBreakpoints"
    end
    return true
  end,
  disassembly = function(state)
    if state.adapter.supportsDisassembleRequest == false then
      return false, "this adapter does not implement disassemble"
    end
    return true
  end,
  qemu_monitor = function(state)
    if not state.monitor then
      return false, "there is no QEMU monitor behind this target"
    end
    return true
  end,
}

function M.state(session)
  session = session or require("dap").session()
  if not session then
    return nil
  end
  local cfg = session.config or {}
  local caps = M.get(session)
  local program = cfg.program
  local info = program and require("dbg.discover").elf_debug_info(program) or nil
  return {
    kind = caps and caps.kind or "unknown",
    backend = cfg.type,
    request = cfg.request,
    program = program and vim.fs.basename(program) or nil,
    debug_info = info or "unknown",
    monitor = caps and caps.monitor or false,
    adapter = session.capabilities or {},
  }
end

-- Unknown features are allowed rather than silently blocked, so this can only
-- ever refuse something it actually knows about.
function M.supports(feature, session)
  local check = FEATURES[feature]
  if not check then
    return true
  end
  local state = M.state(session)
  if not state then
    return false, "no debug session is running"
  end
  return check(state)
end

function M.require(feature, session)
  local ok, reason = M.supports(feature, session)
  if not ok then
    require("dbg.notify").warn(reason or ("unsupported: " .. feature))
  end
  return ok, reason
end

local function classify(caps)
  if caps.symbols.init_task or caps.symbols.linux_banner or caps.symbols.swapper_pg_dir then
    return "kernel"
  end
  if caps.symbols.__libc_start_main or caps.symbols.environ or caps.symbols.main_arena then
    return "userspace"
  end
  return "bare"
end

function M.detect(session, cb)
  session = session or gdbq.session()
  if not session then
    cb(nil)
    return
  end
  local k = key(session)
  if cache[k] then
    cb(cache[k])
    return
  end
  local cfg = session.config or {}
  if cfg.type ~= "gdb" and cfg.type ~= "gdb_kernel" then
    local caps = {
      backend = cfg.type,
      symbols = {},
      commands = {},
      registers = {},
      monitor = false,
      kind = cfg.request == "attach" and "bare" or "userspace",
    }
    cache[k] = caps
    cb(caps)
    return
  end

  local sym_probe = ("python print(' '.join([n for n in %s if gdb.lookup_global_symbol(n) is not None or gdb.lookup_static_symbol(n) is not None]))"):format(
    vim.json.encode(SYMBOLS):gsub('"', "'")
  )
  local cmd_probe = ("python print(' '.join([c for c in %s if c in gdb.execute('complete '+c, to_string=True).split()]))"):format(
    vim.json.encode(COMMANDS):gsub('"', "'")
  )
  local reg_probe = "python print(' '.join([r.name for r in gdb.newest_frame().architecture().registers()]))"

  gdbq.run_all({ sym_probe, cmd_probe, reg_probe, "monitor info version" }, function(out)
    local caps = { backend = cfg.type, symbols = {}, commands = {}, registers = {} }
    for word in tostring(out[sym_probe] or ""):gmatch("%S+") do
      caps.symbols[word] = true
    end
    for word in tostring(out[cmd_probe] or ""):gmatch("%S+") do
      caps.commands[word] = true
    end
    for word in tostring(out[reg_probe] or ""):gmatch("%S+") do
      caps.registers[word] = true
    end
    local mon = tostring(out["monitor info version"] or "")
    caps.monitor = mon ~= "" and not mon:find("Undefined") and not mon:find("^<")
    caps.kind = classify(caps)
    cache[k] = caps
    cb(caps)
  end)
end

function M.describe(caps)
  if not caps then
    return "no session"
  end
  local extras = {}
  for _, name in ipairs({ "vmmap", "kearly", "lx-version", "heap" }) do
    if caps.commands[name] then
      extras[#extras + 1] = name
    end
  end
  return ("%s%s%s"):format(
    caps.kind,
    caps.monitor and " + qemu monitor" or "",
    #extras > 0 and ("  [" .. table.concat(extras, " ") .. "]") or ""
  )
end

return M
