local scan = require("features.lang.c.all_ifdef_branches.source_scanner")

local M = { enabled = false }

local NAME = "clangd"
local MAX_VARIANTS = 8

local FILETYPES = {}

for _, filetype in ipairs(require("features.lang.c.all_ifdef_branches.filetypes")) do
  FILETYPES[filetype] = true
end

local POSITION = {
  ["textDocument/hover"] = true,
  ["textDocument/definition"] = true,
  ["textDocument/declaration"] = true,
  ["textDocument/typeDefinition"] = true,
  ["textDocument/implementation"] = true,
  ["textDocument/references"] = true,
  ["textDocument/documentHighlight"] = true,
  ["textDocument/completion"] = true,
  ["textDocument/signatureHelp"] = true,
  ["textDocument/rename"] = true,
  ["textDocument/prepareRename"] = true,
  ["textDocument/prepareCallHierarchy"] = true,
  ["textDocument/prepareTypeHierarchy"] = true,
  ["textDocument/symbolInfo"] = true,
}

local TOKENS = {
  ["textDocument/semanticTokens/full"] = true,
  ["textDocument/semanticTokens/full/delta"] = true,
  ["textDocument/semanticTokens/range"] = true,
}

local PASS = {
  ["initialize"] = true,
  ["shutdown"] = true,
  ["completionItem/resolve"] = true,
  ["callHierarchy/incomingCalls"] = true,
  ["callHierarchy/outgoingCalls"] = true,
  ["typeHierarchy/supertypes"] = true,
  ["typeHierarchy/subtypes"] = true,
}

local STRIP = {
  "documentFormattingProvider",
  "documentRangeFormattingProvider",
  "documentOnTypeFormattingProvider",
  "documentSymbolProvider",
  "workspaceSymbolProvider",
  "foldingRangeProvider",
  "codeLensProvider",
  "documentLinkProvider",
  "inlayHintProvider",
  "codeActionProvider",
  "executeCommandProvider",
  "selectionRangeProvider",
  "astProvider",
  "diagnosticProvider",
  "colorProvider",
  "memoryUsageProvider",
}

local by_buf, by_uri = {}, {}
local hooked = {}
local variants = {}
local group

local function state_file()
  return require("features.util.storage").path("state", "all_ifdef_branches")
end

local function comment_index(legend)
  for i, t in ipairs(legend and legend.tokenTypes or {}) do
    if t == "comment" then
      return i - 1
    end
  end
end

local function apply_edits(old, edits)
  table.sort(edits, function(a, b)
    return a.start < b.start
  end)

  local out, pos = {}, 0

  for _, e in ipairs(edits) do
    for i = pos + 1, e.start do
      out[#out + 1] = old[i]
    end

    for _, v in ipairs(e.data or {}) do
      out[#out + 1] = v
    end

    pos = e.start + (e.deleteCount or 0)
  end

  for i = pos + 1, #old do
    out[#out + 1] = old[i]
  end

  return out
end

-- Drops the inactive-code (comment) tokens and reports their lines; keep_comment(line) keeps one where no other
-- client draws that line.
local function strip(data, cidx, keep_line, keep_comment)
  local out, dropped = {}, {}
  local line, col, last_line, last_col = 0, 0, 0, 0

  for i = 1, #data, 5 do
    if data[i] > 0 then
      line, col = line + data[i], data[i + 1]
    else
      col = col + data[i + 1]
    end

    local ty = data[i + 3]
    local is_inactive = ty == cidx
    local is_kept

    if is_inactive then
      dropped[line] = true
      is_kept = keep_comment ~= nil and keep_comment(line)
    else
      is_kept = not keep_line or keep_line(line)
    end

    if is_kept then
      local dl = line - last_line

      out[#out + 1] = dl
      out[#out + 1] = dl == 0 and col - last_col or col
      out[#out + 1] = data[i + 2]
      out[#out + 1] = ty
      out[#out + 1] = data[i + 4]
      last_line, last_col = line, col
    end
  end

  return out, dropped
end

-- Full results kept per document by resultId, the last KEPT_RESULTS: a late answer to a request Neovim cancelled
-- must not replace the one Neovim holds and sends deltas against.
local KEPT_RESULTS = 3

local function token_tracker()
  local docs = {}

  local function keep(uri, id, data)
    local doc = docs[uri] or { by_id = {}, order = {} }

    docs[uri] = doc
    if not doc.by_id[id] then
      doc.order[#doc.order + 1] = id
    end

    doc.by_id[id] = data
    if #doc.order > KEPT_RESULTS then
      doc.by_id[table.remove(doc.order, 1)] = nil
    end
  end

  -- Returns the result to pass on, the inactive lines of a full result, and true when the edits had no known base
  -- (nothing is passed on then, and the caller asks for a full result).
  return function(cidx, method, params, result, keep_line, keep_comment)
    if type(result) ~= "table" or not cidx then
      return result
    end

    local uri = params.textDocument.uri
    local data

    if result.data then
      data = result.data
    elseif result.edits then
      local base = docs[uri] and docs[uri].by_id[params.previousResultId]

      -- Edits against unstripped tokens this side no longer holds: Neovim would apply them to its stripped copy.
      if not base then
        docs[uri] = nil

        return nil, nil, true
      end

      data = apply_edits(base, result.edits)
    else
      return result
    end

    local whole = method ~= "textDocument/semanticTokens/range"

    if whole and result.resultId then
      keep(uri, result.resultId, data)
    end

    local kept, dropped = strip(data, cidx, keep_line, keep_comment)

    return { resultId = result.resultId, data = kept }, whole and dropped or nil
  end, function(uri)
    docs[uri] = nil
  end
end

local fake_id = 0

local function empty_reply(callback, notify_reply)
  fake_id = fake_id - 1
  local id = fake_id

  vim.schedule(function()
    if notify_reply then
      notify_reply(id)
    end

    callback(nil, nil, id)
  end)

  return true, id
end

local function owner_of(uri, line)
  local st = by_uri[uri]

  return st and st.owners[line] or 0
end

local function variant_key(st, k)
  return st.root .. "\0" .. k
end

local function live(id)
  local c = id and vim.lsp.get_client_by_id(id)

  return c and not c:is_stopped() and c or nil
end

-- Whether a variant draws the line: it owns it, is attached, and has sent its tokens. Until then the main server keeps
-- the line dimmed (more branches than MAX_VARIANTS, a variant that failed to start, a hidden buffer, start-up).
local function drawn_by_variant(uri, line)
  local st = by_uri[uri]
  local k = st and st.owners[line] or 0

  if k == 0 or not st.ready[k] then
    return false
  end

  local c = live(variants[variant_key(st, k)])

  return c ~= nil and c.attached_buffers[st.buf] == true
end

-- One full refresh for a burst of variants coming up.
local function refresh_soon(st)
  if st.refresh_pending then
    return
  end

  st.refresh_pending = true
  vim.defer_fn(function()
    st.refresh_pending = false
    if by_buf[st.buf] == st and vim.api.nvim_buf_is_loaded(st.buf) then
      pcall(vim.lsp.semantic_tokens.force_refresh, st.buf)
    end
  end, 100)
end

local function owner_at_cursor(bufnr)
  if bufnr == nil or vim.in_fast_event() then
    return nil
  end

  local cur = vim.api.nvim_get_current_buf()

  if bufnr == 0 then
    bufnr = cur
  end

  local st = bufnr == cur and by_buf[bufnr]

  if not st then
    return nil
  end

  return st.owners[vim.api.nvim_win_get_cursor(0)[1] - 1] or 0
end

local gated = setmetatable({}, { __mode = "k" })

-- Neovim asks every client that supports a method; the gate leaves one per request, by the cursor's line, as every
-- positional request of this configuration is made at the cursor (no mouse hover). Requests for another buffer
-- are not gated; the request hooks below answer those by position.
local function gate(client, who)
  if gated[client] then
    return
  end

  gated[client] = { orig = rawget(client, "supports_method") }
  local base = getmetatable(client).supports_method

  client.supports_method = function(self, method, bufnr)
    if self ~= client then
      self, method, bufnr = client, self, method
    end

    local ok = base(self, method, bufnr)

    if ok and M.enabled and POSITION[method] then
      local owner = owner_at_cursor(bufnr)

      if owner ~= nil then
        return owner == who
      end
    end

    return ok
  end
end

local function hook_main(client)
  if hooked[client.id] then
    return
  end

  local rpc = client.rpc
  local request = rpc.request
  local cidx = comment_index(vim.tbl_get(client.server_capabilities or {}, "semanticTokensProvider", "legend"))
  local track, forget = token_tracker()

  hooked[client.id] = { rpc = rpc, request = request, forget = forget }
  rpc.request = function(method, params, callback, notify_reply)
    local td = M.enabled and type(params) == "table" and params.textDocument

    if td then
      if POSITION[method] and params.position and owner_of(td.uri, params.position.line) > 0 then
        return empty_reply(callback, notify_reply)
      end

      if TOKENS[method] then
        local cb = callback

        callback = function(err, result, id)
          if not err then
            local dropped, unknown_base

            result, dropped, unknown_base = track(cidx, method, params, result, nil, function(line)
              return not drawn_by_variant(td.uri, line)
            end)

            if dropped then
              M._on_inactive(td.uri, dropped)
            end

            if unknown_base and by_uri[td.uri] then
              refresh_soon(by_uri[td.uri])
            end
          end

          return cb(err, result, id)
        end
      end
    end

    return request(method, params, callback, notify_reply)
  end

  gate(client, 0)
end

local function unhook_main(id)
  local h = hooked[id]

  if not h then
    return
  end

  h.rpc.request = h.request
  hooked[id] = nil
  local client = vim.lsp.get_client_by_id(id)

  if client and gated[client] then
    client.supports_method = gated[client].orig
    gated[client] = nil
  end
end

function M._rewrite(uri, k, text)
  local st = by_uri[uri]
  local assign = st and st.assigns[k]

  if not assign or type(text) ~= "string" then
    return text
  end

  return scan.rewrite_text(text, assign)
end

local function proxy(rpc, k)
  local cidx
  local track, forget = token_tracker()

  return {
    is_closing = rpc.is_closing,
    terminate = rpc.terminate,
    notify = function(method, params)
      if method == "textDocument/didOpen" then
        local td = params.textDocument

        params = {
          textDocument = {
            uri = td.uri,
            languageId = td.languageId,
            version = td.version,
            text = M._rewrite(td.uri, k, td.text),
          },
        }
      elseif method == "textDocument/didChange" then
        local ch = params.contentChanges

        if #ch == 1 and not ch[1].range then
          params = {
            textDocument = params.textDocument,
            contentChanges = { { text = M._rewrite(params.textDocument.uri, k, ch[1].text) } },
          }
        end
      elseif method == "textDocument/didClose" then
        forget(params.textDocument.uri)
      elseif method == "$/cancelRequest" and type(params.id) == "number" and params.id < 0 then
        return true
      end

      return rpc.notify(method, params)
    end,
    request = function(method, params, callback, notify_reply)
      if method == "initialize" then
        local cb = callback

        callback = function(err, result, id)
          cidx = comment_index(vim.tbl_get(result or {}, "capabilities", "semanticTokensProvider", "legend"))

          return cb(err, result, id)
        end
      elseif TOKENS[method] then
        local cb, uri = callback, params.textDocument.uri

        callback = function(err, result, id)
          if not err then
            local tracked, _, unknown_base = track(cidx, method, params, result, function(line)
              return owner_of(uri, line) == k
            end)

            result = tracked

            local st = by_uri[uri]

            if st and (unknown_base or (result and not st.ready[k])) then
              st.ready[k] = result ~= nil or nil
              refresh_soon(st)
            end
          end

          return cb(err, result, id)
        end
      elseif not PASS[method] then
        local td = type(params) == "table" and params.textDocument
        local pos = type(params) == "table" and params.position

        if not (POSITION[method] and td and pos and owner_of(td.uri, pos.line) == k) then
          return empty_reply(callback, notify_reply)
        end
      end

      return rpc.request(method, params, callback, notify_reply)
    end,
  }
end

local function variant_cmd(main)
  local cmd = main.config.cmd
  local out = {}

  if type(cmd) == "table" then
    for i, a in ipairs(cmd) do
      if i == 1 or not (a:find("^%-%-background%-index") or a:find("^%-%-clang%-tidy") or a:find("^%-j=")) then
        out[#out + 1] = a
      end
    end
  else
    out = { NAME, "--log=error" }
  end

  vim.list_extend(out, { "--background-index=false", "--clang-tidy=false", "-j=2" })

  return out
end

local function variant_config(main, k)
  local mc = main.config
  local init_options = vim.deepcopy(mc.init_options or {})

  init_options.clangdFileStatus = false
  local function noop() end

  return {
    name = NAME .. "~" .. k,
    cmd = function(dispatchers)
      return proxy(vim.lsp.rpc.start(variant_cmd(main), dispatchers, { cwd = mc.cmd_cwd, env = mc.cmd_env }), k)
    end,
    root_dir = main.root_dir,
    workspace_folders = main.workspace_folders,
    capabilities = vim.deepcopy(mc.capabilities),
    init_options = init_options,
    get_language_id = mc.get_language_id,
    flags = { allow_incremental_sync = false, debounce_text_changes = 300 },
    handlers = {
      ["textDocument/publishDiagnostics"] = noop,
      ["$/progress"] = noop,
      ["window/showMessage"] = noop,
      ["window/logMessage"] = noop,
      ["textDocument/clangd.fileStatus"] = noop,
    },
    on_init = function(client, result)
      if result and result.offsetEncoding then
        client.offset_encoding = result.offsetEncoding
      end

      for _, key in ipairs(STRIP) do
        client.server_capabilities[key] = nil
      end

      gate(client, k)
    end,
  }
end

local function attach_variant(st, k)
  local key = variant_key(st, k)
  local c = live(variants[key])

  if c then
    if not c.attached_buffers[st.buf] then
      vim.lsp.buf_attach_client(st.buf, c.id)
    end

    return c.id, false
  end

  local main = vim.lsp.get_client_by_id(st.main)

  if not main then
    return nil
  end

  local id = vim.lsp.start(variant_config(main, k), {
    bufnr = st.buf,
    reuse_client = function()
      return false
    end,
  })

  variants[key] = id

  return id, true
end

local function detach_variant(st, k)
  local c = live(variants[variant_key(st, k)])

  if c and c.attached_buffers[st.buf] then
    vim.lsp.buf_detach_client(st.buf, c.id)
  end
end

local function stop_idle()
  vim.defer_fn(function()
    for key, id in pairs(variants) do
      local c = live(id)

      if not c then
        variants[key] = nil
      elseif vim.tbl_isempty(c.attached_buffers) then
        c:stop()
        variants[key] = nil
      end
    end
  end, 3000)
end

local function signature(map)
  local t = {}

  for key, v in pairs(map) do
    t[#t + 1] = key .. "=" .. v
  end

  table.sort(t)

  return table.concat(t, "\29")
end

local function recompute(st)
  if not (M.enabled and by_buf[st.buf] == st and st.inactive and vim.api.nvim_buf_is_loaded(st.buf)) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(st.buf, 0, -1, false)
  local tree = scan.parse(lines)

  scan.classify(tree, lines, st.inactive)
  local list = vim.list_slice(scan.cover(tree), 1, MAX_VARIANTS)
  local shown = #vim.fn.win_findbuf(st.buf) > 0
  local assigns, keys = {}, {}

  for k, a in ipairs(list) do
    assigns[k] = scan.by_sig(tree, a)
    keys[k] = signature(assigns[k])
  end

  local owners = scan.owners(tree, st.inactive, list)
  local owners_key = signature(owners)
  local old_keys = st.keys
  local refresh = owners_key ~= st.owners_key

  st.assigns, st.keys, st.owners, st.owners_key = assigns, keys, owners, owners_key
  for k = 1, math.max(#assigns, st.n) do
    if k <= #assigns and shown then
      local id, fresh = attach_variant(st, k)

      if id and not fresh and old_keys[k] and old_keys[k] ~= keys[k] then
        st.ready[k] = nil
        vim.lsp.buf_detach_client(st.buf, id)
        vim.lsp.buf_attach_client(st.buf, id)
      end
    else
      st.ready[k] = nil
      detach_variant(st, k)
    end
  end

  if #assigns < st.n or not shown then
    stop_idle()
  end

  st.n = #assigns
  if refresh and shown then
    vim.lsp.semantic_tokens.force_refresh(st.buf)
  end
end

local function schedule(st, delay)
  st.tick = st.tick + 1
  local tick = st.tick

  vim.defer_fn(function()
    if st.tick == tick then
      recompute(st)
    end
  end, delay)
end

function M._on_inactive(uri, dropped)
  local st = by_uri[uri]

  if st then
    st.inactive = dropped
    schedule(st, 120)
  end
end

local function track(buf, client)
  if by_buf[buf] or not vim.api.nvim_buf_is_loaded(buf) or not FILETYPES[vim.bo[buf].filetype] then
    return
  end

  local uri = vim.uri_from_bufnr(buf)
  local st = {
    buf = buf,
    uri = uri,
    main = client.id,
    root = client.root_dir or vim.fn.getcwd(),
    owners = {},
    assigns = {},
    keys = {},
    -- [k] = true once variant k has sent its tokens for this buffer.
    ready = {},
    n = 0,
    tick = 0,
  }

  by_buf[buf], by_uri[uri] = st, st
  hook_main(client)
  vim.lsp.semantic_tokens.force_refresh(buf)
end

local function untrack(buf)
  local st = by_buf[buf]

  if not st then
    return
  end

  by_buf[buf] = nil
  if by_uri[st.uri] == st then
    by_uri[st.uri] = nil
  end

  local main = hooked[st.main]

  if main then
    main.forget(st.uri)
  end

  for k = 1, st.n do
    detach_variant(st, k)
  end

  stop_idle()
end

function M.enable()
  if M.enabled then
    return
  end

  M.enabled = true
  group = vim.api.nvim_create_augroup("all_ifdef_branches", { clear = true })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)

      if client and client.name == NAME then
        track(args.buf, client)
      end
    end,
  })

  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    callback = function(args)
      local st = by_buf[args.buf]

      if st and st.main == args.data.client_id then
        untrack(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    callback = function(args)
      untrack(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(args)
      local st = by_buf[args.buf]

      if st and st.inactive then
        schedule(st, 50)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    callback = function(args)
      local st = by_buf[args.buf]

      if st then
        schedule(st, 5000)
      end
    end,
  })

  for _, client in ipairs(vim.lsp.get_clients({ name = NAME })) do
    for buf in pairs(client.attached_buffers) do
      track(buf, client)
    end
  end
end

function M.disable()
  if not M.enabled then
    return
  end

  M.enabled = false
  if group then
    vim.api.nvim_del_augroup_by_id(group)
    group = nil
  end

  local bufs = vim.tbl_keys(by_buf)

  for _, buf in ipairs(bufs) do
    untrack(buf)
  end

  for key, id in pairs(variants) do
    local c = live(id)

    if c then
      c:stop()
    end

    variants[key] = nil
  end

  for id in pairs(hooked) do
    unhook_main(id)
  end

  for _, buf in ipairs(bufs) do
    if vim.api.nvim_buf_is_loaded(buf) then
      vim.lsp.semantic_tokens.force_refresh(buf)
    end
  end
end

function M.set(on)
  if on then
    M.enable()
  else
    M.disable()
  end

  local path = state_file()

  if on then
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile({ "on" }, path)
  else
    os.remove(path)
  end
end

function M.toggle()
  M.set(not M.enabled)
end

local watcher

local function follow_state()
  local on = vim.uv.fs_stat(state_file()) ~= nil

  if on ~= M.enabled then
    if on then
      M.enable()
    else
      M.disable()
    end
  end
end

function M.setup()
  local path = state_file()
  local dir, name = vim.fs.dirname(path), vim.fs.basename(path)

  vim.fn.mkdir(dir, "p")
  if not watcher then
    watcher = vim.uv.new_fs_event()
    if watcher then
      watcher:start(dir, {}, function(err, fname)
        if not err and fname == name then
          vim.schedule(follow_state)
        end
      end)
    end
  end

  follow_state()
end

function M._debug(buf)
  local st = by_buf[buf or vim.api.nvim_get_current_buf()]
  local ids = {}

  for key, id in pairs(variants) do
    ids[key:gsub("%z", "#")] = id
  end

  return { tracked = st ~= nil, n = st and st.n, owners = st and vim.tbl_count(st.owners), variants = ids }
end

return M
