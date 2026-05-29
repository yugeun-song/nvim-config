local util = require("lsp_filter.util")

local M = {}

local ACTIONS = { disable = true, diagnostics_off = true }

local config = {
  marker_names = { ".nvim-lsp-filter.json" },
  markers_enabled = false,
  default_servers = { "clangd" },
  default_action = "disable",
  data_file = nil,
}

local global_rules = {}

local function to_server_set(servers)
  if servers == nil then
    return nil
  end
  if servers == "*" then
    return "*"
  end
  if type(servers) == "string" then
    servers = { servers }
  end
  if type(servers) ~= "table" then
    return nil
  end
  local set = {}
  for _, s in ipairs(servers) do
    if s == "*" then
      return "*"
    end
    if type(s) == "string" and s ~= "" then
      set[s] = true
    end
  end
  if next(set) == nil then
    return nil
  end
  return set
end

local function normalize_rule(raw, allow_no_matcher)
  if type(raw) ~= "table" then
    return nil, "rule is not a table"
  end
  local action = raw.action or config.default_action
  if not ACTIONS[action] then
    return nil, "invalid action: " .. tostring(action)
  end
  local servers_src = raw.servers
  if servers_src == nil then
    servers_src = config.default_servers
  end
  local servers = to_server_set(servers_src)
  if servers == nil then
    return nil, "invalid servers"
  end
  local rule = { action = action, servers = servers }
  local has_matcher = false
  if type(raw.contains) == "string" and raw.contains ~= "" then
    rule.contains = raw.contains
    has_matcher = true
  end
  if type(raw.within) == "string" and raw.within ~= "" then
    local w = util.normalize(raw.within)
    if w then
      rule.within = w
      has_matcher = true
    end
  end
  if not has_matcher and not allow_no_matcher then
    return nil, "rule has no matcher (need 'contains' or 'within')"
  end
  return rule
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
end

function M.data_file()
  return config.data_file
end

function M.marker_names()
  return config.marker_names
end

local function ingest(into, source_data, source_name)
  if type(source_data) ~= "table" then
    return
  end
  local arr = source_data.rules
  if arr == nil then
    arr = source_data
  end
  if type(arr) ~= "table" then
    return
  end
  for i, raw in ipairs(arr) do
    local rule, err = normalize_rule(raw, false)
    if rule then
      into[#into + 1] = rule
    else
      util.warn(string.format("skipped invalid rule #%d from %s: %s", i, source_name, err or "?"))
    end
  end
end

function M.load(inline_rules)
  local loaded = {}
  ingest(loaded, inline_rules, "inline opts")
  if config.data_file then
    local data, err = util.read_json(config.data_file)
    if err then
      util.warn(err)
    elseif data then
      ingest(loaded, data, "data file")
    end
  end
  global_rules = loaded
  return loaded
end

local function matches_path(rule, npath)
  if rule.contains and util.has_segment(npath, rule.contains) then
    return true
  end
  if rule.within and util.is_within(npath, rule.within) then
    return true
  end
  return false
end

local function server_matches(rule, server)
  if rule.servers == "*" then
    return true
  end
  return type(rule.servers) == "table" and rule.servers[server] == true
end

function M.decide(bufpath, server)
  local npath = util.normalize(bufpath)
  if not npath then
    return nil
  end

  local marker = config.markers_enabled and util.find_upward(npath, config.marker_names) or nil
  if marker then
    local data, err = util.read_json(marker)
    if err then
      util.warn(err)
    elseif data then
      local arr = data.rules
      if arr == nil then
        arr = data
      end
      if type(arr) == "table" then
        for _, raw in ipairs(arr) do
          local rule = normalize_rule(raw, true)
          if rule and server_matches(rule, server) then
            local applies
            if rule.contains or rule.within then
              applies = matches_path(rule, npath)
            else
              applies = true
            end
            if applies then
              return rule.action, "marker:" .. marker
            end
          end
        end
      end
    end
  end

  for _, rule in ipairs(global_rules) do
    if matches_path(rule, npath) and server_matches(rule, server) then
      return rule.action, "global"
    end
  end

  return nil
end

function M.get_global_rules()
  return global_rules
end

return M
