local M = {}

-- GDB answers `setFunctionBreakpoints` and `setInstructionBreakpoints`, but
-- nvim-dap has no API for either, so the list is kept here and pushed to the
-- session.  This is what keeps a binary built without -g usable: `break main`
-- depends on no line table.
local functions = {}
local addresses = {}
local status = {}

local function notify()
  return require("dbg.notify")
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
  if not require("dbg.context").is_low_level(session) then
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
  if caps.supportsInstructionBreakpoints ~= false and #addresses > 0 then
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
  if require("dbg.context").block_if_managed_session("Breaking on a function name or address") then
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
  if require("dbg.context").block_if_managed_session("Breaking on a function name or address") then
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

function M.setup(dap)
  -- Queued before nvim-dap's own breakpoints and configurationDone, so these
  -- arrive before the target is running.
  dap.listeners.before.event_initialized["dbg_breakpoints"] = function(session)
    if not require("dbg.context").is_low_level(session) then
      return
    end
    status = {}
    M.sync(session)
  end
end

return M
