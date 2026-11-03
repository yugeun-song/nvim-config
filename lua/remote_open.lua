local M = {}

function M.focus_dir()
  local base = vim.env.XDG_RUNTIME_DIR and vim.fn.stdpath("run") or vim.fn.stdpath("state")
  return vim.fs.joinpath(base, "nvim-focus")
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

function M.targets()
  local dir, found = M.focus_dir(), {}
  for name in vim.fs.dir(dir) do
    local pid = tonumber(name)
    local path = vim.fs.joinpath(dir, name)
    if pid and vim.uv.kill(pid, 0) == 0 then
      local stat = vim.uv.fs_stat(path)
      local ok, lines = pcall(vim.fn.readfile, path)
      if stat and ok and lines[1] and lines[1] ~= "" then
        found[#found + 1] = { addr = lines[1], pid = pid, mtime = stat.mtime.sec * 1e9 + stat.mtime.nsec }
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

function M.setup()
  local group = vim.api.nvim_create_augroup("remote_open", { clear = true })
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
