local script_dir = vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(arg[0], ":p")))
package.path = vim.fs.joinpath(script_dir, "..", "lua", "?.lua") .. ";" .. package.path
local remote_open = require("remote_open")

local file = arg[1]
local line = math.max(math.floor(tonumber(arg[2] or "") or 1), 1)
local col = math.max(math.floor(tonumber(arg[3] or "") or 1), 1)
if not file or file == "" then
  io.stderr:write("usage: nvim -l open-at.lua FILE [LINE [COLUMN]]\n")
  os.exit(2)
end
file = vim.fs.normalize(vim.fn.fnamemodify(file, ":p"))

local deadline = assert(vim.uv.new_timer())
deadline:start(5000, 0, function()
  os.exit(3)
end)

local function open_in(addr)
  local ok, ch = pcall(vim.fn.sockconnect, "pipe", addr, { rpc = true })
  if not ok or ch == 0 then
    return false
  end
  local opened = pcall(function()
    vim.rpcrequest(ch, "nvim_cmd", { cmd = "stopinsert" }, {})
    vim.rpcrequest(ch, "nvim_cmd", { cmd = "drop", args = { vim.fn.fnameescape(file) } }, {})
  end)
  if opened then
    pcall(function()
      local row = math.min(line, vim.rpcrequest(ch, "nvim_buf_line_count", 0))
      local text = vim.rpcrequest(ch, "nvim_buf_get_lines", 0, row - 1, row, false)[1] or ""
      vim.rpcrequest(ch, "nvim_win_set_cursor", 0, { row, math.min(col - 1, math.max(#text - 1, 0)) })
      vim.rpcrequest(ch, "nvim_cmd", { cmd = "normal", args = { "zz" }, bang = true }, {})
    end)
  end
  pcall(vim.fn.chanclose, ch)
  return opened
end

local function parent(pid)
  if vim.fn.has("win32") == 1 then
    local query = ("(Get-CimInstance Win32_Process -Filter 'ProcessId=%d').ParentProcessId"):format(pid)
    return tonumber(vim.trim(vim.fn.system({ "powershell", "-NoProfile", "-Command", query })))
  end
  local f = io.open("/proc/" .. pid .. "/stat")
  if f then
    local stat = f:read("*a")
    f:close()
    return tonumber(stat:match("%) %S+ (%d+)"))
  end
  return tonumber(vim.trim(vim.fn.system({ "ps", "-o", "ppid=", "-p", tostring(pid) })))
end

local function lineage(pid)
  local depth = vim.fn.has("win32") == 1 and 4 or 16
  local pids = {}
  while pid and pid > 1 and #pids < depth do
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
    available = function()
      return vim.fn.has("win32") == 1
    end,
    raise = function(pids)
      for _, pid in ipairs(pids) do
        local activate = ("(New-Object -ComObject WScript.Shell).AppActivate(%d)"):format(pid)
        if vim.fn.system({ "powershell", "-NoProfile", "-Command", activate }):find("True") then
          return true
        end
      end
      return false
    end,
  },
}

local function raise(pid)
  for _, backend in ipairs(RAISE) do
    if backend.available() then
      return backend.raise(lineage(pid))
    end
  end
  return false
end

for _, target in ipairs(remote_open.targets()) do
  if open_in(target.addr) then
    raise(target.pid)
    return
  end
end
if vim.fn.executable("neovide") == 1 then
  vim.fn.jobstart({ "neovide", "--", "+" .. line, file }, { detach = true })
else
  io.stderr:write("open-at: no running Neovim to send " .. file .. " to, and no neovide to start\n")
  os.exit(1)
end
