local file, line, col = arg[1], tonumber(arg[2] or "") or 1, tonumber(arg[3] or "") or 1
if not file or file == "" then
  io.stderr:write("usage: nvim -l open-at.lua FILE [LINE [COLUMN]]\n")
  os.exit(2)
end
file = vim.fs.normalize(vim.fn.fnamemodify(file, ":p"))
line, col = math.max(line, 1), math.max(col, 1)

vim.defer_fn(function()
  os.exit(3)
end, 5000)

local function target()
  local ok, lines = pcall(vim.fn.readfile, vim.fn.stdpath("run") .. "/nvim-last-focus")
  if ok and lines[1] and lines[1] ~= "" then
    return lines[1], tonumber(lines[2])
  end
end

local function open_in(addr)
  local ok, ch = pcall(vim.fn.sockconnect, "pipe", addr, { rpc = true })
  if not ok or ch == 0 then
    return false
  end
  local done = pcall(function()
    vim.rpcrequest(ch, "nvim_exec2", "stopinsert | drop " .. vim.fn.fnameescape(file), {})
    local row = math.min(line, vim.rpcrequest(ch, "nvim_buf_line_count", 0))
    local text = vim.rpcrequest(ch, "nvim_buf_get_lines", 0, row - 1, row, false)[1] or ""
    vim.rpcrequest(ch, "nvim_win_set_cursor", 0, { row, math.min(col - 1, math.max(#text - 1, 0)) })
    vim.rpcrequest(ch, "nvim_exec2", "normal! zz", {})
  end)
  pcall(vim.fn.chanclose, ch)
  return done
end

local function parent(pid)
  local f = io.open("/proc/" .. pid .. "/stat")
  if not f then
    return nil
  end
  local stat = f:read("*a")
  f:close()
  return tonumber(stat:match("%) %S+ (%d+)"))
end

local function raise(pid)
  if not pid or not vim.env.HYPRLAND_INSTANCE_SIGNATURE or vim.fn.executable("hyprctl") == 0 then
    return
  end
  local ok, clients = pcall(vim.json.decode, vim.fn.system({ "hyprctl", "-j", "clients" }))
  if not ok or type(clients) ~= "table" then
    return
  end
  local windows = {}
  for _, c in ipairs(clients) do
    if type(c) == "table" and c.pid and c.address then
      windows[c.pid] = c.address
    end
  end
  for _ = 1, 16 do
    if windows[pid] then
      vim.fn.system({ "hyprctl", "dispatch", "focuswindow", "address:" .. windows[pid] })
      return
    end
    pid = parent(pid)
    if not pid or pid <= 1 then
      return
    end
  end
end

local addr, pid = target()
if addr and open_in(addr) then
  raise(pid)
elseif vim.fn.executable("neovide") == 1 then
  vim.fn.jobstart({ "neovide", "--", "+" .. line, file }, { detach = true })
else
  io.stderr:write("open-at: no running Neovim to send " .. file .. " to, and no neovide to start\n")
  os.exit(1)
end
