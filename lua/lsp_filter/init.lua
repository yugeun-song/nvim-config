local util = require("lsp_filter.util")
local rules = require("lsp_filter.rules")

local M = {}

local state = {
  registry = nil,
  enabled = true,
  inline = nil,
  default_servers = { "clangd" },
  group = nil,
}

local function default_registry()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "lsp_filter", "rules.json")
end

function M.registry_path()
  return state.registry or default_registry()
end

local function detach_client(bufnr, client)
  if type(vim.lsp.buf_detach_client) == "function" then
    if pcall(vim.lsp.buf_detach_client, bufnr, client.id) then
      return
    end
  end
  pcall(function()
    vim.lsp.stop_client(client.id, false)
  end)
end

local function apply(bufnr, client)
  if not state.enabled then
    return
  end
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" then
    return
  end
  local action = rules.decide(bufname, client.name)
  if action == "disable" then
    vim.schedule(function()
      detach_client(bufnr, client)
    end)
  elseif action == "diagnostics_off" then
    vim.schedule(function()
      pcall(vim.diagnostic.enable, false, { bufnr = bufnr })
    end)
  end
end

local function reapply_open_buffers()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        apply(bufnr, client)
      end
    end
  end
end

function M.reload()
  rules.load(state.inline)
  reapply_open_buffers()
  vim.notify("[lsp_filter] reloaded (" .. #rules.get_global_rules() .. " global rule(s))")
end

local function servers_signature(servers)
  if servers == "*" then
    return "*"
  end
  if type(servers) == "table" then
    local t = {}
    for _, s in ipairs(servers) do
      t[#t + 1] = s
    end
    table.sort(t)
    return table.concat(t, ",")
  end
  return tostring(servers)
end

local function same_rule(a, b)
  if (a.action or "") ~= (b.action or "") then
    return false
  end
  if (a.within or "") ~= (b.within or "") then
    return false
  end
  if (a.contains or "") ~= (b.contains or "") then
    return false
  end
  return servers_signature(a.servers) == servers_signature(b.servers)
end

function M.add_rule(raw)
  if type(raw) ~= "table" or (not raw.within and not raw.contains) then
    vim.notify("[lsp_filter] invalid rule (need within or contains)", vim.log.levels.WARN)
    return false
  end
  local registry = M.registry_path()
  local current, err = util.read_json(registry)
  if err then
    vim.notify(
      "[lsp_filter] registry is malformed; fix it first (aborting to avoid data loss):\n" .. err,
      vim.log.levels.ERROR
    )
    return false
  end
  if current == nil then
    current = { rules = {} }
  end
  if type(current.rules) ~= "table" then
    current.rules = {}
  end
  for _, existing in ipairs(current.rules) do
    if same_rule(existing, raw) then
      vim.notify("[lsp_filter] rule already present: " .. (raw.within or raw.contains))
      return true
    end
  end
  current.rules[#current.rules + 1] = raw
  local ok, werr = util.write_json(registry, current)
  if not ok then
    vim.notify("[lsp_filter] failed to write registry: " .. tostring(werr), vim.log.levels.ERROR)
    return false
  end
  M.reload()
  vim.notify("[lsp_filter] added " .. (raw.within or raw.contains) .. " [" .. servers_signature(raw.servers) .. " / " .. raw.action .. "]")
  return true
end

local function ancestors_of(path)
  local n = util.normalize(path)
  if not n then
    return {}
  end
  local items = { n }
  local dir = vim.fs.dirname(n)
  while dir and dir ~= "" do
    items[#items + 1] = dir
    local parent = vim.fs.dirname(dir)
    if parent == dir then
      break
    end
    dir = parent
  end
  return items
end

function M.add_current_file()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    vim.notify("[lsp_filter] no file in current buffer", vim.log.levels.WARN)
    return
  end
  M.add_rule({ within = util.normalize(path), servers = vim.deepcopy(state.default_servers), action = "disable" })
end

function M.add_current_dir()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    vim.notify("[lsp_filter] no file in current buffer", vim.log.levels.WARN)
    return
  end
  local items = ancestors_of(path)
  if #items == 0 then
    return
  end
  vim.ui.select(items, { prompt = "lsp_filter: exclude which path?" }, function(choice)
    if not choice then
      return
    end
    M.add_rule({ within = choice, servers = vim.deepcopy(state.default_servers), action = "disable" })
  end)
end

local function pick_action_then_add(within, servers)
  vim.ui.select({ "disable", "diagnostics_off" }, { prompt = "lsp_filter: action?" }, function(action)
    if not action then
      return
    end
    M.add_rule({ within = within, servers = servers, action = action })
  end)
end

function M.add_advanced()
  local cur = vim.api.nvim_buf_get_name(0)
  local default_path = cur ~= "" and vim.fs.dirname(util.normalize(cur) or cur) or vim.fn.getcwd()
  vim.ui.input({ prompt = "lsp_filter: path to exclude: ", default = default_path, completion = "dir" }, function(input)
    if not input or input == "" then
      return
    end
    local within = util.normalize(input)
    if not within then
      vim.notify("[lsp_filter] invalid path", vim.log.levels.WARN)
      return
    end
    vim.ui.select({ "clangd", "all servers", "custom..." }, { prompt = "lsp_filter: servers?" }, function(choice)
      if not choice then
        return
      end
      if choice == "clangd" then
        pick_action_then_add(within, { "clangd" })
      elseif choice == "all servers" then
        pick_action_then_add(within, "*")
      else
        vim.ui.input({ prompt = "lsp_filter: server names (comma-separated): " }, function(csv)
          if not csv or csv == "" then
            return
          end
          local list = {}
          for s in csv:gmatch("[^,%s]+") do
            list[#list + 1] = s
          end
          if #list == 0 then
            return
          end
          pick_action_then_add(within, list)
        end)
      end
    end)
  end)
end

function M.list_current()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    vim.notify("[lsp_filter] no file in current buffer", vim.log.levels.WARN)
    return
  end
  local names = {}
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    names[#names + 1] = c.name
  end
  if #names == 0 then
    names = state.default_servers
  end
  local lines = { "lsp_filter: " .. (util.normalize(path) or path) }
  for _, name in ipairs(names) do
    local action, source = rules.decide(path, name)
    lines[#lines + 1] = "  " .. name .. " -> " .. (action or "(no rule)") .. (source and ("  <- " .. source) or "")
  end
  vim.notify(table.concat(lines, "\n"))
end

function M.edit_registry()
  local registry = M.registry_path()
  if not util.is_file(registry) then
    local ok = util.write_json(registry, { rules = {} })
    if not ok then
      vim.notify("[lsp_filter] cannot create registry file", vim.log.levels.ERROR)
      return
    end
  end
  vim.cmd.edit(vim.fn.fnameescape(registry))
end

function M.toggle()
  state.enabled = not state.enabled
  vim.notify("[lsp_filter] " .. (state.enabled and "enabled" or "disabled (session)"))
  if state.enabled then
    reapply_open_buffers()
  end
end

function M.setup(opts)
  opts = opts or {}
  state.registry = opts.registry or default_registry()
  state.inline = opts.rules
  state.default_servers = opts.default_servers or { "clangd" }
  state.enabled = true

  rules.setup({
    data_file = state.registry,
    default_servers = state.default_servers,
    default_action = opts.default_action or "disable",
    markers_enabled = opts.markers_enabled == true,
    marker_names = opts.marker_names or { ".nvim-lsp-filter.json" },
  })
  rules.load(state.inline)

  state.group = vim.api.nvim_create_augroup("lsp_filter", { clear = true })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = state.group,
    callback = function(args)
      pcall(function()
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client then
          apply(args.buf, client)
        end
      end)
    end,
    desc = "lsp_filter: gate LSP servers per path rules",
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = state.group,
    callback = function(args)
      local name = util.normalize(vim.api.nvim_buf_get_name(args.buf))
      if name and state.registry and name == util.normalize(state.registry) then
        M.reload()
      end
    end,
    desc = "lsp_filter: reload registry on save",
  })
end

return M
