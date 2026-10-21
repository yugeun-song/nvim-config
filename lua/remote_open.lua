local M = {}

function M.focus_file()
  return vim.fn.stdpath("run") .. "/nvim-last-focus"
end

local function record()
  local addr = vim.v.servername
  if addr == "" or #vim.api.nvim_list_uis() == 0 then
    return
  end
  local path = M.focus_file()
  local tmp = path .. "." .. vim.fn.getpid()
  if pcall(vim.fn.writefile, { addr, tostring(vim.fn.getpid()) }, tmp) then
    os.rename(tmp, path)
  end
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
      local ok, lines = pcall(vim.fn.readfile, M.focus_file())
      if ok and lines[1] == vim.v.servername then
        os.remove(M.focus_file())
      end
    end,
    desc = "Stop being the scripts/open-at.lua target",
  })
end

return M
