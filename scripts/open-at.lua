local script_dir = vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(arg[0], ":p")))

package.path = vim.fs.joinpath(script_dir, "..", "lua", "?.lua") .. ";" .. package.path
local remote_open = require("features.editor.open_in_running_instance")

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

for _, target in ipairs(remote_open.targets()) do
  if open_in(target.addr) then
    remote_open.raise(target.pid)

    return
  end
end

if vim.fn.executable("neovide") == 1 then
  vim.fn.jobstart({ "neovide", "--", "+" .. line, file }, { detach = true })
else
  io.stderr:write("open-at: no running Neovim to send " .. file .. " to, and no neovide to start\n")
  os.exit(1)
end
