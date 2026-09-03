-- Execution-context classifier. The config layer injects the profile (a config
-- declares dbg_profile, or the adapter type implies it); this module only reads
-- it. Default is "managed" so a non-gdb adapter never gets the gdb/kernel UI.
local M = {}

-- Fallback when a config does not declare dbg_profile. gdb == usermode C/C++/asm,
-- gdb_kernel == Linux kernel; everything else stays managed. The kernel panels
-- are Linux-specific, so the profile names it as such.
local PROFILE_BY_TYPE = { gdb_kernel = "linux_kernel", gdb = "native" }

-- Classify a raw config the same way as M.of, before a session exists.
function M.profile_of_config(cfg)
  cfg = cfg or {}
  return cfg.dbg_profile or PROFILE_BY_TYPE[cfg.type] or "managed"
end

function M.of(session)
  session = session or (package.loaded["dap"] and require("dap").session()) or nil
  if not session then
    return "managed"
  end
  return M.profile_of_config(session.config or {})
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

-- Same guard, but only while a session runs: with none up it is plain cleanup.
function M.block_if_managed_session(what)
  local ok, dap = pcall(require, "dap")
  if not (ok and dap.session()) then
    return false
  end
  return M.block_if_managed(what)
end

-- A managed session keeps nvim-dap-view's winbar as set up. A gdb one gets the
-- ring the configuration layer injects, since it owns the panels the ring names.
local low_level = nil
local stock = nil

function M.set_low_level_winbar(spec)
  low_level = spec
end

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

local function remember_stock(cfg)
  if stock then
    return
  end
  local labels = {}
  for name, section in pairs(cfg.winbar.base_sections or {}) do
    labels[name] = section.label
  end
  stock = {
    sections = vim.deepcopy(cfg.winbar.sections),
    default_section = cfg.winbar.default_section,
    show_keymap_hints = cfg.winbar.show_keymap_hints,
    labels = labels,
  }
end

local function put(cfg, want)
  local base = cfg.winbar.base_sections or {}
  local custom = cfg.winbar.custom_sections or {}
  local filtered = {}
  for _, name in ipairs(want.sections) do
    if base[name] or custom[name] then
      filtered[#filtered + 1] = name
    end
  end
  if #filtered == 0 then
    filtered = vim.deepcopy(want.sections)
  end
  cfg.winbar.sections = filtered
  cfg.winbar.default_section = vim.tbl_contains(filtered, want.default_section) and want.default_section or filtered[1]
  cfg.winbar.show_keymap_hints = want.show_keymap_hints
  for name, section in pairs(base) do
    section.label = (want.labels or {})[name] or stock.labels[name]
  end
  return filtered
end

-- The selected section outlives a session, so a gdb one can leave Registers
-- showing and nvim-dap-view restores it on its next open. Move the selection
-- itself, not just the window, when the ring no longer lists it.
local function reselect(cfg, filtered)
  local ok, state = pcall(require, "dap-view.state")
  if not ok or not state.current_section then
    return
  end
  if vim.tbl_contains(filtered, state.current_section) then
    return
  end
  -- wrapped_action moves the selection itself, and it has to see the OLD one as
  -- last_section: only then does nvim-dap-view put its own buffer back in the
  -- window and swap the section keymaps. Assigning first makes its new_view test
  -- false, and a gdb panel buffer stays on screen inside a managed session.
  local target = cfg.winbar.default_section
  pcall(function()
    require("dap-view.options.winbar").wrapped_action(target)
  end)
  if state.current_section ~= target then
    state.current_section = target      -- no window to act on; at least do not restore a gdb section
  end
end

function M.apply_winbar(session)
  local cfg = dapview_config()
  if not cfg then
    return
  end
  remember_stock(cfg)
  local want = (not M.is_managed(session)) and low_level or stock
  local filtered = put(cfg, want or stock)
  pcall(function()
    require("dap-view.options.winbar").refresh_winbar()
  end)
  reselect(cfg, filtered)
end


return M
