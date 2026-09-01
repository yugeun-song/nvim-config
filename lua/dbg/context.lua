-- Execution-context classifier. The config layer injects the profile (a config
-- declares dbg_profile, or the adapter type implies it); this module only reads
-- it. Default is "managed" so a non-gdb adapter never gets the gdb/kernel UI.
local M = {}

-- Fallback when a config does not declare dbg_profile. gdb == usermode C/C++/asm,
-- gdb_kernel == Linux kernel; everything else stays managed. The kernel panels
-- are Linux-specific, so the profile names it as such.
local PROFILE_BY_TYPE = { gdb_kernel = "linux_kernel", gdb = "native" }

function M.of(session)
  session = session or (package.loaded["dap"] and require("dap").session()) or nil
  if not session then
    return "managed"
  end
  local cfg = session.config or {}
  return cfg.dbg_profile or PROFILE_BY_TYPE[cfg.type] or "managed"
end

function M.is_kernel(s)
  return M.of(s) == "linux_kernel"
end
function M.is_native(s)
  return M.of(s) == "native"
end
function M.is_low_level(s)
  local p = M.of(s)
  return p == "linux_kernel" or p == "native"
end
function M.is_managed(s)
  return M.of(s) == "managed"
end

-- Guard a gdb-only panel from a managed session: notify once and report blocked.
function M.block_if_managed(what, session)
  if M.is_managed(session) then
    require("dbg.notify").info((what or "This view") .. " is available for gdb (C/C++ or Linux Kernel) sessions.")
    return true
  end
  return false
end

-- A managed session uses nvim-dap-view's own sections; a low-level one keeps the
-- full custom set. The full set is captured from the configured superset so it is
-- never duplicated here.
local MANAGED_SECTIONS = { "scopes", "watches", "exceptions", "breakpoints", "threads", "sessions", "repl", "console" }
local full_sections = nil

local function dapview_config()
  -- nvim-dap-view's setup() rebinds its config to a new merged table, so the live
  -- winbar reads require("dap-view.setup").config, not the defaults module.
  local ok, cfg = pcall(function()
    return require("dap-view.setup").config
  end)
  if ok and cfg and cfg.winbar then
    return cfg
  end
end

function M.apply_winbar(session)
  local cfg = dapview_config()
  if not cfg then
    return
  end
  full_sections = full_sections or vim.deepcopy(cfg.winbar.sections)
  local want = M.is_managed(session) and MANAGED_SECTIONS or full_sections
  local base = cfg.winbar.base_sections or {}
  local custom = cfg.winbar.custom_sections or {}
  local filtered = {}
  for _, s in ipairs(want) do
    if base[s] or custom[s] then
      filtered[#filtered + 1] = s
    end
  end
  if #filtered == 0 then
    filtered = vim.deepcopy(want)
  end
  cfg.winbar.sections = filtered
  cfg.winbar.default_section = filtered[1] or cfg.winbar.default_section
  pcall(function()
    require("dap-view.options.winbar").refresh_winbar()
  end)
end

function M.reset_winbar()
  local cfg = dapview_config()
  if cfg and full_sections then
    cfg.winbar.sections = vim.deepcopy(full_sections)
    cfg.winbar.default_section = full_sections[1]
  end
end

return M
