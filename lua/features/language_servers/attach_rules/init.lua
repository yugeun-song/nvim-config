local util = require("features.language_servers.attach_rules.path_and_file_helpers")
local rules = require("features.language_servers.attach_rules.rules")

local M = {}

local state = {
  registry = nil,
  enabled = true,
  inline = nil,
  group = nil,
  -- [bufnr][namespace] = true for the diagnostics a rule turned off, so they come back when it goes.
  silenced = {},
}

local function default_registry()
  return require("features.maintenance.local_storage").path("data", "language_server_attach_rules.json")
end

function M.registry_path()
  return state.registry or default_registry()
end

local function detach_client(bufnr, client)
  if pcall(vim.lsp.buf_detach_client, bufnr, client.id) then
    if next(client.attached_buffers) == nil then
      client:stop()
    end

    return
  end

  pcall(function()
    client:stop(false)
  end)
end

-- The client's diagnostic namespaces: pushed, pulled, and pulled per registration (named after the client).
local function client_namespaces(client)
  local found = {
    [vim.lsp.diagnostic.get_namespace(client.id, false)] = true,
    [vim.lsp.diagnostic.get_namespace(client.id, true)] = true,
  }

  local prefix = ("nvim.lsp.%s.%d."):format(client.name, client.id)

  for name, ns in pairs(vim.api.nvim_get_namespaces()) do
    if vim.startswith(name, prefix) then
      found[ns] = true
    end
  end

  return found
end

local function silence(bufnr, client)
  local silenced = state.silenced[bufnr] or {}

  state.silenced[bufnr] = silenced
  for ns in pairs(client_namespaces(client)) do
    silenced[ns] = true
    pcall(vim.diagnostic.enable, false, { bufnr = bufnr, ns_id = ns })
  end
end

local function unsilence(bufnr, client)
  local silenced = state.silenced[bufnr]

  if not silenced then
    return
  end

  for ns in pairs(client_namespaces(client)) do
    if silenced[ns] then
      silenced[ns] = nil
      pcall(vim.diagnostic.enable, true, { bufnr = bufnr, ns_id = ns })
    end
  end
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
      silence(bufnr, client)
    end)
  else
    unsilence(bufnr, client)
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
  util.notify("reloaded (" .. #rules.get_global_rules() .. " global rule(s))")
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
    util.notify("invalid rule (need within or contains)", vim.log.levels.WARN)

    return false
  end

  local registry = M.registry_path()
  local current, err = util.read_json(registry)

  if err then
    util.notify("registry cannot be used; fix it first (aborting to avoid data loss):\n" .. err, vim.log.levels.ERROR)

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
      util.notify("rule already present: " .. (raw.within or raw.contains))

      return true
    end
  end

  current.rules[#current.rules + 1] = raw
  local ok, werr = util.write_json(registry, current)

  if not ok then
    util.notify("failed to write registry: " .. tostring(werr), vim.log.levels.ERROR)

    return false
  end

  M.reload()
  util.notify(
    "added " .. (raw.within or raw.contains) .. " [" .. servers_signature(raw.servers) .. " / " .. raw.action .. "]"
  )

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
    util.notify("no file in current buffer", vim.log.levels.WARN)

    return
  end

  M.add_rule({ within = util.normalize(path), servers = vim.deepcopy(rules.default_servers()), action = "disable" })
end

function M.add_current_dir()
  local path = vim.api.nvim_buf_get_name(0)

  if path == "" then
    util.notify("no file in current buffer", vim.log.levels.WARN)

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

    M.add_rule({ within = choice, servers = vim.deepcopy(rules.default_servers()), action = "disable" })
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
      util.notify("invalid path", vim.log.levels.WARN)

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
    util.notify("no file in current buffer", vim.log.levels.WARN)

    return
  end

  local names = {}

  for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    names[#names + 1] = c.name
  end

  if #names == 0 then
    names = rules.default_servers()
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
      util.notify("cannot create registry file", vim.log.levels.ERROR)

      return
    end
  end

  vim.cmd.edit(vim.fn.fnameescape(registry))
end

function M.toggle()
  state.enabled = not state.enabled
  util.notify(state.enabled and "enabled" or "disabled (session)")
  if state.enabled then
    reapply_open_buffers()
  end
end

function M.setup(opts)
  opts = opts or {}
  state.registry = opts.registry or default_registry()
  state.inline = opts.rules
  state.enabled = true

  rules.setup({
    data_file = state.registry,
    default_servers = opts.default_servers,
    default_action = opts.default_action,
    markers_enabled = opts.markers_enabled,
    marker_names = opts.marker_names,
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

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = state.group,
    callback = function(args)
      state.silenced[args.buf] = nil
    end,
    desc = "lsp_filter: forget what a wiped buffer had turned off",
  })
end

return M
