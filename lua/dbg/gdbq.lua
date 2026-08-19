local M = {}

function M.strip_ansi(s)
  s = tostring(s or "")
  s = s:gsub("\27%[[%d;:?]*[ -/]*[@-~]", "")
  s = s:gsub("\27%][^\7\27]*[\7\27]?", "")
  s = s:gsub("\r", "")
  return s
end

function M.session()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return nil
  end
  return dap.session()
end

function M.run(cmd, cb, opts)
  opts = opts or {}
  local session = opts.session or M.session()
  if not session then
    cb(nil, "no session")
    return
  end
  local frame = session.current_frame
  session:request("evaluate", {
    expression = cmd,
    context = "repl",
    frameId = frame and frame.id,
  }, function(err, res)
    if err then
      cb(nil, err.message or "command failed")
      return
    end
    cb(M.strip_ansi((res or {}).result or ""))
  end)
end

function M.run_all(cmds, cb)
  local out, pending = {}, #cmds
  if pending == 0 then
    cb(out)
    return
  end
  for _, cmd in ipairs(cmds) do
    M.run(cmd, function(text, err)
      out[cmd] = text or ("<" .. tostring(err) .. ">")
      pending = pending - 1
      if pending == 0 then
        vim.schedule(function()
          cb(out)
        end)
      end
    end)
  end
end

function M.has_pwndbg(cb)
  M.run("pwndbg --help", function(text)
    cb(text ~= nil and not tostring(text):find("Undefined command"))
  end)
end

return M
