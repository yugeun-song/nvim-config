-- One search at a time: a new one cancels the last; a notice after 1 s, a stop at 30 s. argv lists, never a shell.
local M = {}

M.TITLE = "Code search"
M.MAX_RESULTS = 5000

local NOTICE_MS = 1000
local LIMIT_MS = 30000

local active

function M.notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = M.TITLE })
end

local function close(timer)
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

local function settle(job)
  close(job.notice)
  close(job.limit)

  if active == job then
    active = nil
  end
end

function M.cancel()
  local job = active

  if job then
    settle(job)
    pcall(job.stop)
  end
end

-- start(done) begins the search and returns its stop function; only the latest search reaches show.
function M.run(what, start, show)
  M.cancel()

  local job = { stop = function() end }

  active = job
  job.notice = vim.defer_fn(function()
    if active == job then
      M.notify(("Searching %s ..."):format(what))
    end
  end, NOTICE_MS)
  job.limit = vim.defer_fn(function()
    if active == job then
      M.cancel()
      M.notify(("%s found nothing within %d s"):format(what, LIMIT_MS / 1000), vim.log.levels.ERROR)
    end
  end, LIMIT_MS)

  local ok, stop = pcall(start, function(...)
    if active == job then
      settle(job)
      show(...)
    end
  end)

  if not ok then
    settle(job)
    M.notify(("%s failed: %s"):format(what, stop), vim.log.levels.ERROR)
  elseif type(stop) == "function" then
    job.stop = stop
  end
end

-- argv's stdout lines, at most MAX_RESULTS; done(lines, result, truncated) on the main loop. Returns a stop function.
function M.lines(argv, cwd, done)
  local lines, rest, truncated = {}, "", false
  local proc
  local ok, err = pcall(function()
    proc = vim.system(argv, {
      cwd = cwd,
      text = true,
      stdout = function(_, data)
        if not data or truncated then
          return
        end

        data = rest .. data

        local from = 1

        while true do
          local newline = data:find("\n", from, true)

          if not newline then
            break
          end

          lines[#lines + 1] = data:sub(from, newline - 1):gsub("\r$", "")
          from = newline + 1

          if #lines >= M.MAX_RESULTS then
            truncated = true
            pcall(proc.kill, proc, "sigterm")

            break
          end
        end

        rest = truncated and "" or data:sub(from)
      end,
    }, function(result)
      if rest ~= "" and not truncated then
        lines[#lines + 1] = rest
      end

      vim.schedule(function()
        done(lines, result, truncated)
      end)
    end)
  end)

  if not ok then
    vim.schedule(function()
      done({}, { code = -1, stderr = tostring(err) }, false)
    end)

    return function() end
  end

  return function()
    pcall(proc.kill, proc, "sigterm")
  end
end

-- A failed tool's message: its first stderr line without its prefix, plus rg's and fd's "error:" line.
function M.failure(name, result)
  local lines = vim.split(vim.trim(result.stderr or ""), "\n", { trimempty = true })
  local first = lines[1] and vim.trim(lines[1]):gsub("^%[?[%w_-]+[%w_ -]*%]?:%s*", "", 1)

  if not first or first == "" then
    return ("%s: exit code %s"):format(name, tostring(result.code))
  end

  for i = 2, #lines do
    if vim.startswith(vim.trim(lines[i]), "error:") then
      return ("%s: %s %s"):format(name, first, vim.trim(lines[i]))
    end
  end

  return ("%s: %s"):format(name, first)
end

return M
