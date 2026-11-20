-- The buffer whose name is a path, compared as a name. vim.fn.bufnr(name) reads it as a file pattern (k[1].cu, k?.cu
-- and k*.cu all find k1.cu), so a debugger's frame or a language server's URI could pick another buffer.
local M = {}

-- File names compare without case where the file system does.
local FOLD = vim.fn.has("win32") == 1 or vim.fn.has("mac") == 1

local function key(path)
  local normalized = vim.fs.normalize(path, { expand_env = false })

  return FOLD and normalized:lower() or normalized
end

---@param path string an absolute path
---@return integer? buf
function M.find(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  local want = key(path)

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)

    if name ~= "" and key(name) == want then
      return buf
    end
  end

  return nil
end

return M
