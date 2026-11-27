-- WSL only: connects WSL Neovim to the host Windows UI's IME/Caps Lock state via
-- `windows_ime_helper.exe wsl-watch-input-state <ui_pid>` without requiring appendWindowsPath=true.
local M = {}

local uv = vim.uv
local WSL = vim.fn.has("wsl") == 1
local HELPER_EXE_NAME = "^windows_ime_helper%-%x+%-%x+%.exe$"
local HELPER_DIR_SUFFIX = "/nvim-config/windows_ime_helper"

local function has_control(text)
  return text:find("[%z\1-\31\127]") ~= nil
end

local function validate_env(ui_pid, helper_dir, helper_exe)
  if type(ui_pid) ~= "string" or not ui_pid:match("^%d+$") then
    return nil, "invalid NVIM_WSL_UI_PID"
  end

  local pid = tonumber(ui_pid)

  if not pid or pid < 1 or pid > 4294967295 then
    return nil, "NVIM_WSL_UI_PID out of range"
  end

  if type(helper_dir) ~= "string" or helper_dir == "" or has_control(helper_dir) or helper_dir:sub(1, 1) ~= "/" then
    return nil, "invalid NVIM_WSL_HOST_HELPER_DIR"
  end

  local clean_dir = helper_dir:gsub("/+$", "")

  if
    clean_dir:find("/../", 1, true)
    or clean_dir:match("/%.%.$")
    or clean_dir:sub(-#HELPER_DIR_SUFFIX) ~= HELPER_DIR_SUFFIX
  then
    return nil, "NVIM_WSL_HOST_HELPER_DIR must point to nvim-config/windows_ime_helper"
  end

  if type(helper_exe) ~= "string" or not helper_exe:match(HELPER_EXE_NAME) then
    return nil, "invalid NVIM_WSL_HOST_HELPER_EXE"
  end

  return {
    ui_pid = ui_pid,
    dir = clean_dir,
    exe = vim.fs.joinpath(clean_dir, helper_exe),
  }, nil
end

function M.resolve()
  if not WSL then
    return nil, "WSL only"
  end

  local cfg, err = validate_env(
    uv.os_getenv("NVIM_WSL_UI_PID"),
    uv.os_getenv("NVIM_WSL_HOST_HELPER_DIR"),
    uv.os_getenv("NVIM_WSL_HOST_HELPER_EXE")
  )

  if not cfg then
    return nil, err
  end

  local dir_st = uv.fs_stat(cfg.dir)

  if not dir_st or dir_st.type ~= "directory" then
    return nil, "host helper directory is missing"
  end

  local exe_st = uv.fs_lstat(cfg.exe)

  if not exe_st or exe_st.type ~= "file" or exe_st.size <= 0 then
    return nil, "host windows_ime_helper executable is missing"
  end

  return cfg, nil
end

local function accept_output(pending, data)
  local lines = {}
  local text = (pending or "") .. (data or "")
  local start = 1

  while true do
    local stop = text:find("\n", start, true)

    if not stop then
      break
    end

    local line = text:sub(start, stop - 1)

    if not line:match("^[01][01]$") then
      return lines, "", "wsl-watch-input-state: unexpected output"
    end

    lines[#lines + 1] = line
    start = stop + 1
  end

  local rest = text:sub(start)

  if #rest > 64 then
    return lines, "", "wsl-watch-input-state: output without line ends"
  end

  return lines, rest, nil
end

local reports = {}
local reported = {}

local function notify_later(message, level)
  local function show()
    vim.notify(message, level, { title = "wsl_ime_bridge" })
  end

  vim.schedule(function()
    if vim.g.did_very_lazy then
      return show()
    end

    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      once = true,
      callback = function()
        vim.schedule(show)
      end,
    })
  end)
end

function M.report(message, level)
  if type(message) ~= "string" or message == "" then
    return
  end

  message = message:sub(1, 500)
  reports[#reports + 1] = os.date("%H:%M:%S ") .. message
  if #reports > 20 then
    table.remove(reports, 1)
  end

  if not reported[message] then
    reported[message] = true
    notify_later(message, level or vim.log.levels.WARN)
  end
end

function M.reports()
  return vim.deepcopy(reports)
end

local watcher, watch_failure

function M.watch(on_data)
  local cfg = M.resolve()

  if not cfg then
    return nil
  end

  if watcher and not watcher:is_closing() then
    return watcher
  end

  local pending = ""
  local said = ""
  local proc

  local function reject(why)
    watch_failure = why
    pending = ""
    M.report("windows_ime_helper " .. why)
    if proc and not proc:is_closing() then
      pcall(proc.kill, proc, 15)
    end
  end

  local is_spawned, started = pcall(vim.system, { cfg.exe, "wsl-watch-input-state", cfg.ui_pid }, {
    stdin = true,
    stderr = function(_, data)
      if data then
        said = (said .. data):sub(-4096)
      end
    end,
    text = true,
    stdout = function(_, data)
      if not data then
        return
      end

      local lines, rest, why = accept_output(pending, data)

      pending = rest
      for _, line in ipairs(lines) do
        on_data(line)
      end

      if why then
        reject(why)
      elseif #lines > 0 then
        watch_failure = nil
      end
    end,
  }, function(res)
    pending = ""
    watcher = nil
    if res.code ~= 0 and res.signal ~= 15 and not watch_failure then
      local first = vim.trim(said):match("[^\r\n]+")

      watch_failure = ("wsl-watch-input-state: exit %s%s"):format(tostring(res.code), first and (": " .. first) or "")
      M.report("windows_ime_helper " .. watch_failure)
    end
  end)

  if not is_spawned then
    M.report("windows_ime_helper wsl-watch-input-state: could not start: " .. tostring(started))
  end

  proc = is_spawned and started or nil
  watcher = proc

  return watcher
end

function M.send(cmd)
  if (cmd ~= "e" and cmd ~= "p" and cmd ~= "r") or not watcher or watcher:is_closing() then
    return false
  end

  return (pcall(watcher.write, watcher, cmd))
end

function M.watch_failure()
  return watch_failure
end

M._validate_env = validate_env
M._accept_output = accept_output

return M
