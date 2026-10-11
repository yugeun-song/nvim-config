-- The gdb behind a gdb/kernel session exits by itself right after answering a
-- disconnect. nvim-dap closes the session on that answer, shutting stdin and
-- sending SIGINT into the exit; on kernel sessions that has left gdb hung,
-- holding the gdbstub. That close waits for gdb to go first, and Neovim's exit
-- kills what is still there.
--
-- gdb can also stop answering for good when a request lands while it starts
-- the target after configurationDone (seen with the setExceptionBreakpoints
-- nvim-dap-view sends then), so requests wait for the launch or attach answer.
local M = {}

local EXIT_GRACE_MS = 3000

local PASS_WHILE_STARTING = { configurationDone = true, disconnect = true, cancel = true }

local function alive(pid)
  return pid ~= nil and vim.uv.kill(pid, 0) == 0
end

function M.attach(session)
  if session.dbg_adapter then
    return
  end
  local st = { held = {} }
  session.dbg_adapter = st
  local original = session.request
  session.request = function(self, command, args, cb)
    if st.starting and not PASS_WHILE_STARTING[command] then
      local co, main = coroutine.running()
      if not cb and co and not main then
        st.held[#st.held + 1] = {
          command,
          args,
          function(err, resp)
            coroutine.resume(co, err, resp)
          end,
        }
        return coroutine.yield()
      end
      st.held[#st.held + 1] = { command, args, cb }
      return
    end
    if command == "configurationDone" and not st.started then
      st.starting = true
    end
    return original(self, command, args, cb)
  end
  st.release = function()
    st.starting, st.started = false, true
    local held = st.held
    st.held = {}
    if session.closed then
      return
    end
    for _, item in ipairs(held) do
      original(session, item[1], item[2], item[3])
    end
  end
  session:request(
    "evaluate",
    { expression = "python print(__import__('os').getpid())", context = "repl" },
    function(err, resp)
      st.pid = not err and tonumber(((resp or {}).result or ""):match("%d+")) or nil
    end
  )
  local class_close = session.close
  session.close = function(self)
    if st.waiting or not st.exiting or not alive(st.pid) then
      return class_close(self)
    end
    st.waiting = true
    local deadline = vim.uv.now() + EXIT_GRACE_MS
    local timer = vim.uv.new_timer()
    timer:start(
      50,
      50,
      vim.schedule_wrap(function()
        if alive(st.pid) and vim.uv.now() < deadline then
          return
        end
        timer:stop()
        timer:close()
        if not self.closed then
          class_close(self)
        end
      end)
    )
  end
end

local function is_dap_gdb(argv)
  for i = 1, #argv do
    if argv[i] == "--interpreter=dap" or (argv[i] == "-i" and argv[i + 1] == "dap") then
      return true
    end
  end
  return false
end

local function gdb_children()
  local me = vim.fn.getpid()
  local out = {}
  local tasks = vim.uv.fs_scandir("/proc/" .. me .. "/task")
  while tasks do
    local tid = vim.uv.fs_scandir_next(tasks)
    if not tid then
      break
    end
    local list = io.open(("/proc/%d/task/%s/children"):format(me, tid))
    if list then
      for pid in list:read("*a"):gmatch("%d+") do
        local f = io.open("/proc/" .. pid .. "/cmdline", "rb")
        if f then
          if is_dap_gdb(vim.split(f:read("*a"), "\0", { plain = true, trimempty = true })) then
            out[#out + 1] = tonumber(pid)
          end
          f:close()
        end
      end
      list:close()
    end
  end
  return out
end

-- A hung gdb ignores SIGTERM as well, hence the SIGKILL after it.
function M.kill_leftovers()
  local left = gdb_children()
  if #left == 0 then
    return
  end
  for _, pid in ipairs(left) do
    vim.uv.kill(pid, "sigterm")
  end
  vim.wait(500, function()
    return #gdb_children() == 0
  end, 20)
  for _, pid in ipairs(gdb_children()) do
    vim.uv.kill(pid, "sigkill")
  end
end

function M.setup(dap)
  dap.listeners.before.event_initialized["dbg_adapter"] = function(session)
    if require("dbg.context").is_low_level(session) then
      M.attach(session)
    end
  end
  for _, command in ipairs({ "launch", "attach" }) do
    dap.listeners.after[command]["dbg_adapter"] = function(session)
      if session.dbg_adapter then
        session.dbg_adapter.release()
      end
    end
  end
  -- Runs before nvim-dap's own handler of the answer, which closes the session.
  dap.listeners.before.disconnect["dbg_adapter"] = function(session, err)
    if session.dbg_adapter and not err then
      session.dbg_adapter.exiting = true
    end
  end
end

return M
