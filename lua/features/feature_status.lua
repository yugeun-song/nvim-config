-- The three answers every feature's health check gives (lua/features/*/health.lua, :checkhealth features.*):
--   available    supported here and ready                                  (ok)
--   unsupported  not supported on this system, and why                     (info)
--   blocked      supported, but something is missing or wrong, and what    (warn, with advice)
local M = {}

local h = vim.health

M.OS = vim.fn.has("win32") == 1 and "Windows"
  or vim.fn.has("mac") == 1 and "macOS"
  or vim.fn.has("linux") == 1 and "Linux"
  or vim.uv.os_uname().sysname

M.WINDOWS, M.MACOS, M.LINUX = M.OS == "Windows", M.OS == "macOS", M.OS == "Linux"

function M.available(feature, detail)
  h.ok(detail and ("%s: %s"):format(feature, detail) or feature)
end

function M.unsupported(feature, why)
  h.info(("%s: not supported on %s (%s)"):format(feature, M.OS, why))
end

function M.blocked(feature, reason, advice)
  h.warn(("%s: %s"):format(feature, reason), advice)
end

-- The first of the names that is a program on PATH; a table lists alternatives.
function M.find(program)
  for _, name in ipairs(type(program) == "table" and program or { program }) do
    if vim.fn.executable(name) == 1 then
      return name
    end
  end
end

function M.label(program)
  return type(program) == "table" and table.concat(program, " or ") or program
end

-- A feature that needs programs: available with what was found, else blocked with what is missing.
function M.programs(feature, list, advice)
  local found, missing = {}, {}

  for _, program in ipairs(list) do
    local hit = M.find(program)

    if hit then
      found[#found + 1] = hit
    else
      missing[#missing + 1] = M.label(program)
    end
  end

  if #missing == 0 then
    M.available(feature, table.concat(found, ", "))
  else
    M.blocked(feature, "missing " .. table.concat(missing, ", "), advice)
  end

  return #missing == 0
end

-- Whether a plugin of the spec is installed (lazy.nvim's directory for it exists).
function M.plugin_installed(name)
  local plugin = require("lazy.core.config").plugins[name]

  return plugin ~= nil and plugin.dir ~= nil and vim.uv.fs_stat(plugin.dir) ~= nil
end

-- The merged options lazy.nvim hands a plugin, without loading it.
function M.plugin_options(name)
  local plugin = require("lazy.core.config").plugins[name]

  if not plugin then
    return {}
  end

  local ok, options = pcall(require("lazy.core.plugin").values, plugin, "opts", false)

  return ok and options or {}
end

local installed_parsers

-- Whether a tree-sitter parser is installed for lang: nvim-treesitter's own list, else Neovim's bundled ones.
function M.parser(lang)
  if not installed_parsers then
    installed_parsers = {}

    local ok, treesitter = pcall(require, "nvim-treesitter")

    for _, name in ipairs(ok and treesitter.get_installed and treesitter.get_installed() or {}) do
      installed_parsers[name] = true
    end
  end

  if installed_parsers[lang] then
    return true
  end

  local ok, added = pcall(vim.treesitter.language.add, lang)

  return ok and added == true
end

return M
