local M = {}

-- nvim-dap has no API for function or instruction breakpoints, so they live here; `break main` needs no line table.
local functions = {}
local addresses = {}
local status = {}

local function notify()
  return require("features.debugging.sessions.notifications")
end

local function find(list, value)
  for i, v in ipairs(list) do
    if v == value then
      return i
    end
  end

  return nil
end

local function record(kind, list, response)
  for i, bp in ipairs((response or {}).breakpoints or {}) do
    local name = list[i]

    if name then
      status[kind .. ":" .. name] = {
        verified = bp.verified,
        address = bp.instructionReference,
        line = bp.line,
        source = bp.source and (bp.source.name or bp.source.path),
      }
    end
  end
end

function M.sync(session)
  session = session or require("dap").session()
  if not session then
    return
  end

  if not require("features.debugging.sessions.session_profile").has_panels(session) then
    return
  end

  local caps = session.capabilities or {}

  if #functions > 0 and caps.supportsFunctionBreakpoints == false then
    notify().warn("This adapter cannot set breakpoints on a function name")
  end

  if caps.supportsFunctionBreakpoints ~= false then
    local list = {}

    for _, name in ipairs(functions) do
      list[#list + 1] = { name = name }
    end

    session:request("setFunctionBreakpoints", { breakpoints = list }, function(err, resp)
      if not err then
        record("function", functions, resp)
      end
    end)
  end

  if caps.supportsInstructionBreakpoints ~= false then
    local list = {}

    for _, addr in ipairs(addresses) do
      list[#list + 1] = { instructionReference = addr }
    end

    session:request("setInstructionBreakpoints", { breakpoints = list }, function(err, resp)
      if not err then
        record("address", addresses, resp)
      end
    end)
  end
end

function M.toggle(spec)
  spec = vim.trim(spec or "")
  if spec == "" then
    return
  end

  if
    require("features.debugging.sessions.session_profile").block_if_managed_session(
      "Breaking on a function name or address"
    )
  then
    return
  end

  spec = spec:gsub("^%*", "")
  local is_address = spec:match("^0[xX]%x+$") ~= nil
  local list = is_address and addresses or functions
  local kind = is_address and "address" or "function"
  local at = find(list, spec)

  if at then
    table.remove(list, at)
    status[kind .. ":" .. spec] = nil
    notify().info("Removed breakpoint on " .. spec)
  else
    list[#list + 1] = spec
    notify().info("Breakpoint on " .. spec)
  end

  M.sync()
end

function M.clear()
  functions, addresses, status = {}, {}, {}
  M.sync()
  notify().info("Cleared every function and address breakpoint")
end

function M.prompt()
  if
    require("features.debugging.sessions.session_profile").block_if_managed_session(
      "Breaking on a function name or address"
    )
  then
    return
  end

  local default = vim.fn.expand("<cword>")

  vim.ui.input({ prompt = "Break on function or 0xADDRESS: ", default = default }, function(answer)
    if answer then
      M.toggle(answer)
    end
  end)
end

function M.entries()
  local out = {}
  local ok, bps = pcall(function()
    return require("dap.breakpoints").get()
  end)

  if ok then
    for buf, list in pairs(bps or {}) do
      local name = vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) or "?"

      for _, bp in ipairs(list) do
        out[#out + 1] = {
          kind = "line",
          buf = buf,
          line = bp.line,
          label = ("%s:%d"):format(vim.fs.basename(name), bp.line),
          detail = bp.condition and ("if " .. bp.condition) or (bp.logMessage and "log" or ""),
        }
      end
    end
  end

  for _, name in ipairs(functions) do
    local s = status["function:" .. name] or {}

    out[#out + 1] = {
      kind = "function",
      name = name,
      label = name .. "()",
      detail = s.address and (s.address .. (s.source and (" " .. s.source .. ":" .. tostring(s.line)) or ""))
        or (s.verified == false and "unresolved" or "pending"),
    }
  end

  for _, addr in ipairs(addresses) do
    local s = status["address:" .. addr] or {}

    out[#out + 1] = {
      kind = "address",
      name = addr,
      label = addr,
      detail = s.verified == false and "unresolved" or "instruction",
    }
  end

  table.sort(out, function(a, b)
    if a.kind ~= b.kind then
      return a.kind < b.kind
    end

    return a.label < b.label
  end)

  return out
end

function M.pick()
  local items = M.entries()

  if #items == 0 then
    notify().info("No breakpoints are set")

    return
  end

  vim.ui.select(items, {
    prompt = "Breakpoints",
    format_item = function(item)
      local kind = ({ line = "line", ["function"] = "func", address = "addr" })[item.kind] or item.kind

      return ("%-5s %-40s %s"):format(kind, item.label, item.detail or "")
    end,
  }, function(item)
    if not item then
      return
    end

    if item.kind == "line" and item.buf and vim.api.nvim_buf_is_valid(item.buf) then
      vim.api.nvim_set_current_buf(item.buf)
      pcall(vim.api.nvim_win_set_cursor, 0, { item.line, 0 })
      vim.cmd("normal! zz")
    else
      notify().info(item.label .. " " .. (item.detail or ""))
    end
  end)
end

local function same_file(a, b)
  return a == b or (vim.uv.fs_realpath(a) or a) == (vim.uv.fs_realpath(b) or b)
end

-- gdb's own breakpoints (a "stop at main" tbreak, a console break) arrive as "new"; on a line the user already
-- holds, nvim-dap would replace the user's and drop it when the tbreak goes.
local function guard_events(session)
  local class_event = session.event_breakpoint

  session.event_breakpoint = function(self, body)
    local bp = body and body.breakpoint

    -- gdb numbers its internal breakpoints below zero; none of them is the user's.
    if bp and type(bp.id) == "number" and bp.id < 0 then
      return
    end

    local path = bp and bp.source and bp.source.path

    if body and body.reason == "new" and path and bp.line then
      for buf, list in pairs(require("dap.breakpoints").get()) do
        if same_file(vim.api.nvim_buf_get_name(buf), path) then
          for _, held in ipairs(list) do
            if held.line == bp.line then
              return
            end
          end
        end
      end
    end

    return class_event(self, body)
  end
end

local function hex(s)
  return (s:gsub(".", function(c)
    return ("%02x"):format(c:byte())
  end))
end

-- Runs to a line or address through gdb's one-shot breakpoint, keeping the user's: nvim-dap's run_to_cursor
-- clears them all and, from a line without code, never stops again.
function M.run_to(session, where)
  local gdbq = require("features.debugging.sessions.gdb_query")
  local on = { session = session }
  local loc = where.address and ("'*%s'"):format(where.address)
    or ("source=bytes.fromhex('%s').decode(), line=%d"):format(hex(where.source), where.line)

  local make = ("python b = gdb.Breakpoint(%s, internal=True, temporary=True); p = b.pending; "):format(loc)
    .. "gdb._dbg_runto = None if p else b; p and b.delete(); print('pending' if p else 'armed')"

  gdbq.run(make, function(out, err)
    if err or vim.trim(out or "") ~= "armed" then
      notify().warn("Run to cursor: " .. (err or "no code there in the loaded program"))

      return
    end

    local dap = require("dap")
    local key = "dbg_runto_" .. tostring(session.id)

    dap.listeners.after.event_stopped[key] = function(s)
      if s == session then
        dap.listeners.after.event_stopped[key] = nil
        gdbq.run(
          "python r = getattr(gdb, '_dbg_runto', None); r is not None and r.is_valid() and r.delete()",
          function() end,
          on
        )
      end
    end

    vim.schedule(function()
      dap.set_session(session)
      require("features.debugging.sessions.target_session").cont()
    end)
  end, on)
end

function M.setup(dap)
  -- Before nvim-dap's own breakpoints and configurationDone, so the target is not
  -- running yet.
  dap.listeners.before.event_initialized["dbg_breakpoints"] = function(session)
    local context = require("features.debugging.sessions.session_profile")

    if not context.has_panels(session) then
      return
    end

    status = {}
    if context.is_gdb(session) then
      guard_events(session)
    end

    M.sync(session)
  end

  -- gdb answers a breakpoint it cannot place yet with no line, and nvim-dap stamps that on the whole file;
  -- answers follow the request's order, so the line comes from the request.
  dap.listeners.before.setBreakpoints["dbg_breakpoints"] = function(session, err, response, request)
    if err or not require("features.debugging.sessions.session_profile").is_gdb(session) then
      return
    end

    local asked = (request or {}).breakpoints or {}

    for i, bp in ipairs((response or {}).breakpoints or {}) do
      if bp.line == nil and asked[i] then
        bp.line = asked[i].line
      end
    end
  end
end

return M
