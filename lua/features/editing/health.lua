-- :checkhealth features.editing. Formatters and linters are the ones the merged configuration names, checked by what
-- conform and nvim-lint themselves would run.
local status = require("features.feature_status")

local M = {}

-- Names in a formatters_by_ft entry: strings, nested lists of strings; a function decides per buffer and is skipped.
local function names_in(entry, out)
  if type(entry) == "string" then
    out[entry] = true
  elseif type(entry) == "table" then
    for _, item in ipairs(entry) do
      names_in(item, out)
    end
  end

  return out
end

local function formatters()
  local by_ft = status.plugin_options("conform.nvim").formatters_by_ft or {}
  local used = {}

  for ft, entry in pairs(by_ft) do
    for name in pairs(names_in(entry, {})) do
      used[name] = used[name] or {}
      table.insert(used[name], ft)
    end
  end

  local ok, conform = pcall(require, "conform")

  if not ok then
    status.blocked("Formatting", "conform.nvim does not load: " .. tostring(conform))

    return
  end

  local names = vim.tbl_keys(used)

  table.sort(names)
  for _, name in ipairs(names) do
    local info = conform.get_formatter_info(name)
    local fts = table.concat(used[name], ", ")

    if info.available then
      status.available("Formatter " .. name, fts)
    else
      status.blocked("Formatter " .. name, ("%s (for %s)"):format(info.available_msg or "not available", fts))
    end
  end
end

local function linters()
  local options = status.plugin_options("nvim-lint")
  local ok, lint = pcall(require, "lint")

  if not ok then
    status.blocked("Linting", "nvim-lint does not load: " .. tostring(lint))

    return
  end

  local used = {}

  for ft, names in pairs(options.linters_by_ft or {}) do
    for _, name in ipairs(names) do
      used[name] = used[name] or {}
      table.insert(used[name], ft)
    end
  end

  local names = vim.tbl_keys(used)

  table.sort(names)
  for _, name in ipairs(names) do
    local linter = lint.linters[name]
    local fts = table.concat(used[name], ", ")

    if type(linter) == "function" then
      local made, value = pcall(linter)

      linter = made and value or {}
    end

    local cmd = type(linter) == "table" and linter.cmd or nil

    if type(cmd) == "function" then
      local made, value = pcall(cmd)

      cmd = made and value or nil
    end

    if type(cmd) ~= "string" then
      status.blocked("Linter " .. name, "nvim-lint has no command for it (for " .. fts .. ")")
    elseif vim.fn.executable(cmd) == 1 then
      status.available("Linter " .. name, fts)
    else
      status.blocked("Linter " .. name, ("%s is not on PATH (for %s)"):format(cmd, fts))
    end
  end
end

function M.check()
  vim.health.start("Editing")
  status.available("File explorer (mini.files), reload on external change, diagnostics on hold, indent stops")

  if status.find("yazi") then
    status.available("Open Folder", "yazi")
  else
    status.blocked("Open Folder", "yazi is not on PATH (<leader>fp, recent projects, still works)", {
      "https://yazi-rs.github.io/",
    })
  end

  local backend, why = require("features.editing.open_in_running_instance").raise_backend()

  if backend then
    status.available("Open in the running instance (scripts/open-at.lua)", "raises windows through " .. backend.name)
  elseif why and why:find("GNOME") then
    status.unsupported("Window raise for scripts/open-at.lua", why)
  else
    status.blocked("Window raise for scripts/open-at.lua", why or "no way to raise a window found")
  end

  vim.health.start("Formatting and linting")
  formatters()
  linters()
end

return M
