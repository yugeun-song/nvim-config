local M = {}

-- Execution control typed into the console has to go through nvim-dap, not
-- straight to GDB: continuing behind the client's back leaves the panels showing
-- a stop that is over and the frame ids GDB handed out stale, which surfaces
-- later as "list index out of range".
local echo_next_stop = false
local explained = {}

-- Said once per session.  nvim-dap points its marker at the nearest frame that
-- happens to carry a source, which is why a green arrow appears over a glibc
-- header and vanishes again when that marker comes back down.
local function explain_sourceless(session, frame)
  -- Already said at attach time when the whole binary has no DWARF.
  if explained[session.id] or session.dbg_no_debug_info then
    return
  end
  explained[session.id] = true
  local name = (frame and frame.name) or "this frame"
  local prog = (session.config or {}).program
  local why = prog
      and require("dbg.discover").elf_debug_info(prog) == "none"
      and (vim.fs.basename(prog) .. " was built without -g")
    or "there is no line table here"
  require("dbg.notify").warn(
    ("%s cannot be shown in the editor: %s. The disassembly follows the program counter instead."):format(name, why)
  )
end

local function repl(text)
  local ok, mod = pcall(require, "dap.repl")
  if ok then
    pcall(mod.append, text)
  end
end

local function live()
  local session = require("dap").session()
  if not session then
    repl("The program is not being run.")
    return nil
  end
  return session
end

local function step(kind, granularity)
  local session = live()
  if not session then
    return
  end
  local dap = require("dap")
  require("dbg.session").focus(session)
  local opts = granularity and { granularity = granularity } or nil
  echo_next_stop = true
  if kind == "over" then
    dap.step_over(opts)
  elseif kind == "into" then
    dap.step_into(opts)
  else
    dap.step_out(opts)
  end
end

local COMMANDS = {}

local function bind(names, fn)
  for _, name in ipairs(names) do
    COMMANDS[name] = fn
  end
end

bind({ "c", "cont", "continue" }, function()
  if not live() then
    return
  end
  repl("Continuing.")
  echo_next_stop = true
  require("dbg.session").cont()
end)

bind({ "n", "next" }, function()
  step("over")
end)

bind({ "s", "step" }, function()
  step("into")
end)

bind({ "ni", "nexti" }, function()
  step("over", "instruction")
end)

bind({ "si", "stepi" }, function()
  step("into", "instruction")
end)

bind({ "fin", "finish" }, function()
  step("out")
end)

bind({ "q", "quit" }, function()
  if not live() then
    return
  end
  require("dbg.session").stop()
end)

bind({ "k", "kill" }, function()
  if not live() then
    return
  end
  require("dap").terminate()
end)

function M.handles(name)
  return COMMANDS[name] ~= nil
end

-- nvim-dap picks the first frame carrying a source so it has somewhere to jump;
-- without -g that quietly selects the caller, which is why `list` used to show
-- glibc while `bt` said `main`.  Put the selection back on frame 0.
function M.realign(session)
  local thread = session.threads and session.threads[session.stopped_thread_id]
  local top = thread and thread.frames and thread.frames[1]
  if not top or not session.current_frame or session.current_frame.id == top.id then
    return false
  end
  session.current_frame = top
  pcall(function()
    session:_request_scopes(top)
  end)
  return true
end

function M.has_source(frame)
  local src = frame and frame.source
  return src ~= nil and (src.path ~= nil or src.sourceReference ~= nil)
end
local has_source = M.has_source

function M.setup(dap)
  dap.repl.commands = vim.tbl_extend("force", dap.repl.commands, {
    custom_commands = vim.tbl_extend("force", dap.repl.commands.custom_commands or {}, COMMANDS),
  })

  dap.listeners.after.event_stopped["dbg_console"] = function(session)
    if not require("dbg.context").is_low_level(session) then
      return
    end
    local wanted = echo_next_stop
    echo_next_stop = false
    local tries = 0
    local function announce()
      tries = tries + 1
      local frame = session.current_frame
      if not frame then
        if tries < 20 and require("dap").session() == session then
          vim.defer_fn(announce, 50)
        end
        return
      end
      frame = session.current_frame
      if not has_source(frame) then
        explain_sourceless(session, frame)
      elseif not wanted then
        return
      end
      local src = frame.source and (frame.source.name or frame.source.path)
      local where = frame.instructionPointerReference
      repl(
        ("#0  %s%s%s"):format(
          where and (where .. " in ") or "",
          frame.name or "?",
          src and (" at " .. src .. ":" .. tostring(frame.line or "?")) or " ()"
        )
      )
    end
    vim.defer_fn(announce, 60)
  end
end

return M
