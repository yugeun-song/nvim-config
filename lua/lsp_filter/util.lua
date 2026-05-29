local uv = vim.uv or vim.loop

local M = {}

M.is_windows = vim.fn.has("win32") == 1
M.case_insensitive = M.is_windows or vim.fn.has("mac") == 1

local tmp_counter = 0

local MAX_READ_BYTES = 1024 * 1024

function M.normalize(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  path = (path:gsub("\\", "/"))
  local ok, res = pcall(vim.fs.normalize, path, { expand_env = true })
  if ok and type(res) == "string" and res ~= "" then
    return res
  end
  return path
end

local function fold(s)
  if M.case_insensitive then
    return s:lower()
  end
  return s
end

function M.has_segment(path, name)
  local np = M.normalize(path)
  if not np or type(name) ~= "string" or name == "" then
    return false
  end
  local target = fold(name)
  for seg in (fold(np) .. "/"):gmatch("([^/]*)/") do
    if seg == target then
      return true
    end
  end
  return false
end

function M.is_within(path, base)
  local np = M.normalize(path)
  local nb = M.normalize(base)
  if not np or not nb then
    return false
  end
  np = fold(np)
  nb = fold(nb)
  if #nb > 1 and nb:sub(-1) == "/" then
    nb = nb:sub(1, -2)
  end
  if np == nb then
    return true
  end
  return np:sub(1, #nb + 1) == nb .. "/"
end

function M.stat(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local ok, st = pcall(uv.fs_stat, path)
  if ok then
    return st
  end
  return nil
end

function M.lstat(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local ok, st = pcall(uv.fs_lstat, path)
  if ok then
    return st
  end
  return nil
end

function M.exists(path)
  return M.stat(path) ~= nil
end

function M.is_file(path)
  local st = M.stat(path)
  return st ~= nil and st.type == "file"
end

function M.is_dir(path)
  local st = M.stat(path)
  return st ~= nil and st.type == "directory"
end

function M.read_file(path)
  if not M.is_file(path) then
    return nil
  end
  local fd = nil
  local ok, data = pcall(function()
    fd = assert(uv.fs_open(path, "r", 420))
    local st = assert(uv.fs_fstat(fd))
    if st.size == 0 then
      return ""
    end
    if st.size > MAX_READ_BYTES then
      error("file exceeds size limit")
    end
    return assert(uv.fs_read(fd, st.size, 0))
  end)
  if fd then
    pcall(uv.fs_close, fd)
  end
  if ok then
    return data
  end
  return nil
end

function M.read_json(path)
  local raw = M.read_file(path)
  if raw == nil or raw == "" then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, raw)
  if ok and type(decoded) == "table" then
    return decoded
  end
  return nil, "invalid JSON: " .. tostring(path)
end

function M.ensure_parent_dir(path)
  local dir = vim.fs.dirname(path)
  if not dir or dir == "" then
    return false, "no parent directory"
  end
  if M.is_dir(dir) then
    return true
  end
  if M.exists(dir) then
    return false, "parent exists but is not a directory: " .. dir
  end
  local ok, err = pcall(vim.fn.mkdir, dir, "p")
  if ok then
    return true
  end
  return false, "mkdir failed: " .. tostring(err)
end

function M.write_atomic(path, content)
  if type(path) ~= "string" or path == "" then
    return false, "invalid path"
  end
  if type(content) ~= "string" then
    return false, "content must be a string"
  end
  local ok_dir, err_dir = M.ensure_parent_dir(path)
  if not ok_dir then
    return false, err_dir
  end
  local lst = M.lstat(path)
  if lst and lst.type == "link" then
    return false, "refusing to overwrite a symlink: " .. path
  end
  if lst and lst.type ~= "file" then
    return false, "refusing to overwrite non-file: " .. path
  end
  tmp_counter = tmp_counter + 1
  local tmp = path .. ".tmp." .. tostring(uv.os_getpid()) .. "." .. tostring(tmp_counter)
  local fd = nil
  local ok_write, err_write = pcall(function()
    fd = assert(uv.fs_open(tmp, "w", 420))
    assert(uv.fs_write(fd, content, 0))
    assert(uv.fs_fsync(fd))
  end)
  if fd then
    pcall(uv.fs_close, fd)
  end
  if not ok_write then
    pcall(uv.fs_unlink, tmp)
    return false, "write failed: " .. tostring(err_write)
  end
  local ok_rename, err_rename = pcall(uv.fs_rename, tmp, path)
  if not ok_rename then
    pcall(uv.fs_unlink, tmp)
    return false, "rename failed: " .. tostring(err_rename)
  end
  return true
end

function M.write_json(path, tbl)
  if type(tbl) ~= "table" then
    return false, "data must be a table"
  end
  local ok, encoded = pcall(vim.json.encode, tbl)
  if not ok or type(encoded) ~= "string" then
    return false, "json encode failed"
  end
  return M.write_atomic(path, encoded .. "\n")
end

function M.delete_file(path)
  local lst = M.lstat(path)
  if not lst or lst.type ~= "file" then
    return false, "not a regular file"
  end
  local ok, err = pcall(uv.fs_unlink, path)
  if ok then
    return true
  end
  return false, tostring(err)
end

function M.find_upward(start, names)
  local p = M.normalize(start)
  if not p then
    return nil
  end
  local dir = M.is_dir(p) and p or vim.fs.dirname(p)
  if not dir or dir == "" then
    return nil
  end
  local found = vim.fs.find(names, { upward = true, path = dir, type = "file", limit = 1 })
  if found and found[1] then
    return found[1], vim.fs.dirname(found[1])
  end
  return nil
end

function M.warn(msg)
  vim.schedule(function()
    vim.notify("[lsp_filter] " .. tostring(msg), vim.log.levels.WARN)
  end)
end

return M
