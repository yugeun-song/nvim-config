local M = {}

function M.focus_dir()
  return require("features.maintenance.local_storage").path(
    vim.env.XDG_RUNTIME_DIR and "run" or "state",
    "running_instances"
  )
end

local function own_file()
  return vim.fs.joinpath(M.focus_dir(), tostring(vim.fn.getpid()))
end

local function record()
  local addr = vim.v.servername

  if addr == "" or #vim.api.nvim_list_uis() == 0 then
    return
  end

  ---@diagnostic disable-next-line: param-type-mismatch
  vim.fn.mkdir(M.focus_dir(), "p", tonumber("700", 8))
  local path = own_file()
  local tmp = path .. ".tmp"

  if pcall(vim.fn.writefile, { addr }, tmp) then
    vim.uv.fs_rename(tmp, path)
  end
end

-- Whether a Neovim answers at addr: a record outlives a Neovim that was killed (no VimLeavePre), and Windows reuses
-- its process id for any other program.
local function answers(addr)
  local mode = addr:find("^[%w%.%-]+:%d+$") and "tcp" or "pipe"
  local ok, channel = pcall(vim.fn.sockconnect, mode, addr, { rpc = true })

  if not ok or channel == 0 then
    return false
  end

  pcall(vim.fn.chanclose, channel)

  return true
end

-- The running Neovims of this configuration with a UI, the last focused first. Stale records are removed.
function M.targets()
  local dir, found = M.focus_dir(), {}
  local own = vim.uv.os_getpid()

  for name in vim.fs.dir(dir) do
    local pid = tonumber(name)
    local path = vim.fs.joinpath(dir, name)

    if pid and vim.uv.kill(pid, 0) == 0 then
      local stat = vim.uv.fs_stat(path)
      local ok, lines = pcall(vim.fn.readfile, path)

      if stat and ok and lines[1] and lines[1] ~= "" then
        if pid == own or answers(lines[1]) then
          found[#found + 1] = { addr = lines[1], pid = pid, mtime = stat.mtime.sec * 1e9 + stat.mtime.nsec }
        else
          vim.uv.fs_unlink(path)
        end
      end
    elseif pid then
      vim.uv.fs_unlink(path)
    end
  end

  table.sort(found, function(a, b)
    return a.mtime > b.mtime
  end)

  return found
end

-- Windows walks the lineage inside its raise_from, in one process.
local function parent(pid)
  local f = io.open("/proc/" .. pid .. "/stat")

  if f then
    local stat = f:read("*a")

    f:close()

    return tonumber(stat:match("%) %S+ (%d+)"))
  end

  return tonumber(vim.trim(vim.fn.system({ "ps", "-o", "ppid=", "-p", tostring(pid) })))
end

local function lineage(pid)
  local pids = {}

  while pid and pid > 1 and #pids < 16 do
    pids[#pids + 1] = pid
    pid = parent(pid)
  end

  return pids
end

local function decode(cmd)
  local ok, obj = pcall(vim.json.decode, vim.fn.system(cmd))

  return ok and type(obj) == "table" and obj or {}
end

local function focus_first(pids, windows, focus)
  for _, pid in ipairs(pids) do
    if windows[pid] then
      focus(windows[pid])

      return true
    end
  end

  return false
end

local function succeeds(cmd)
  vim.fn.system(cmd)

  return vim.v.shell_error == 0
end

local RAISE = {
  {
    name = "Hyprland",
    available = function()
      return vim.env.HYPRLAND_INSTANCE_SIGNATURE and vim.fn.executable("hyprctl") == 1
    end,
    raise = function(pids)
      local windows = {}

      for _, c in ipairs(decode({ "hyprctl", "-j", "clients" })) do
        if type(c) == "table" and c.pid and c.address then
          windows[c.pid] = c.address
        end
      end

      return focus_first(pids, windows, function(address)
        vim.fn.system({ "hyprctl", "dispatch", "focuswindow", "address:" .. address })
      end)
    end,
  },
  {
    name = "Sway",
    available = function()
      return vim.env.SWAYSOCK and vim.fn.executable("swaymsg") == 1
    end,
    raise = function(pids)
      local windows = {}

      local function walk(node)
        if node.pid and node.id and not windows[node.pid] then
          windows[node.pid] = node.id
        end

        for _, key in ipairs({ "nodes", "floating_nodes" }) do
          for _, child in ipairs(type(node[key]) == "table" and node[key] or {}) do
            if type(child) == "table" then
              walk(child)
            end
          end
        end
      end

      walk(decode({ "swaymsg", "-t", "get_tree" }))

      return focus_first(pids, windows, function(id)
        vim.fn.system({ "swaymsg", ("[con_id=%d] focus"):format(id) })
      end)
    end,
  },
  {
    name = "niri",
    available = function()
      return vim.env.NIRI_SOCKET and vim.fn.executable("niri") == 1
    end,
    raise = function(pids)
      local windows = {}

      for _, w in ipairs(decode({ "niri", "msg", "--json", "windows" })) do
        if type(w) == "table" and w.pid and w.id then
          windows[w.pid] = w.id
        end
      end

      return focus_first(pids, windows, function(id)
        vim.fn.system({ "niri", "msg", "action", "focus-window", "--id", tostring(id) })
      end)
    end,
  },
  {
    name = "KDE Plasma",
    available = function()
      return (vim.env.XDG_CURRENT_DESKTOP or ""):find("KDE") and vim.fn.executable("kdotool") == 1
    end,
    raise = function(pids)
      local script = ("const pids = [%s]; for (const w of workspace.windowList()) "):format(table.concat(pids, ","))
        .. "{ if (pids.includes(w.pid)) { workspace.activeWindow = w; break; } }"

      return succeeds({ "kdotool", "kwinscript", "--inline", script })
    end,
  },
  {
    name = "X11",
    available = function()
      return vim.env.DISPLAY and not vim.env.WAYLAND_DISPLAY and vim.fn.executable("xdotool") == 1
    end,
    raise = function(pids)
      for _, pid in ipairs(pids) do
        local id = vim.fn.system({ "xdotool", "search", "--pid", tostring(pid) }):match("%d+")

        if id then
          return succeeds({ "xdotool", "windowactivate", id })
        end
      end

      return false
    end,
  },
  {
    name = "macOS",
    available = function()
      return vim.fn.has("mac") == 1
    end,
    raise = function(pids)
      for _, pid in ipairs(pids) do
        local script =
          'tell application "System Events" to set frontmost of (first process whose unix id is %d) to true'

        if succeeds({ "osascript", "-e", script:format(pid) }) then
          return true
        end
      end

      return false
    end,
  },
  {
    name = "Windows",
    available = function()
      return vim.fn.has("win32") == 1
    end,
    -- One process for the whole lineage: windows_ime_helper natively, else one PowerShell trying pid and three
    -- ancestors.
    raise_from = function(pid)
      if type(pid) ~= "number" or pid < 1 or pid % 1 ~= 0 then
        return false
      end

      local ime_helper = require("features.windows_platform.windows_ime_helper").path({ build = false })

      if ime_helper then
        local res = vim.system({ ime_helper, "raise-window", ("%d"):format(pid) }, { text = true }):wait(5000)

        if res.code ~= 0 then
          require("features.windows_platform.windows_ime_helper").report_exit("raise-window", res)
        end

        return res.code == 0
      end

      local script = ("$p = %d; for ($i = 0; $i -lt 4 -and $p -gt 1; $i++) { "):format(pid)
        .. "if ((New-Object -ComObject WScript.Shell).AppActivate($p)) { 'True'; break }; "
        .. "$p = (Get-CimInstance Win32_Process -Filter ('ProcessId=' + $p)).ParentProcessId }"

      return vim.fn.system({ "powershell", "-NoProfile", "-Command", script }):find("True") ~= nil
    end,
  },
}

function M.raise_backend()
  for _, backend in ipairs(RAISE) do
    if backend.available() then
      return backend
    end
  end

  if vim.env.WAYLAND_DISPLAY and (vim.env.XDG_CURRENT_DESKTOP or ""):find("GNOME") then
    return nil, "GNOME on Wayland lets no program raise a window"
  end

  return nil, "no window tool for this desktop (hyprctl, swaymsg, niri, kdotool or xdotool)"
end

-- Raises the window of the nearest ancestor of pid that owns one.
function M.raise(pid)
  local backend = M.raise_backend()

  if backend and backend.raise_from then
    return backend.raise_from(pid)
  end

  return backend ~= nil and backend.raise(lineage(pid))
end

function M.setup()
  local group = vim.api.nvim_create_augroup("open_in_running_instance", { clear = true })

  vim.api.nvim_create_autocmd({ "UIEnter", "FocusGained" }, {
    group = group,
    callback = record,
    desc = "Make this instance the one scripts/open-at.lua opens files in",
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      vim.uv.fs_unlink(own_file())
    end,
    desc = "Stop being a scripts/open-at.lua target",
  })
end

return M
