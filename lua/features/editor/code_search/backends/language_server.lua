-- Workspace symbols: clangd in C-family buffers, elsewhere each attached server that answers them.
local search_job = require("features.editor.code_search.search_job")

local M = {}

local METHOD = "workspace/symbol"
local KINDS = { { name = "symbol", label = "workspace symbol" } }

local function answers(client, buf)
  return client:supports_method(METHOD, buf)
end

-- LSP columns count in the server's encoding; a file open here converts exactly, any other as UTF-8.
local function byte_column(position, encoding, buf)
  if encoding == "utf-8" or not buf then
    return position.character
  end

  local line = vim.api.nvim_buf_get_lines(buf, position.line, position.line + 1, false)[1]
  local ok, col = pcall(vim.str_byteindex, line or "", encoding, position.character, false)

  return ok and col or position.character
end

local function entries_of(symbols, encoding)
  local loaded, entries = {}, {}

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      loaded[vim.api.nvim_buf_get_name(buf)] = buf
    end
  end

  for i, symbol in ipairs(symbols) do
    if i > search_job.MAX_RESULTS then
      return entries, true
    end

    local location = symbol.location or {}
    local uri = location.uri or location.targetUri

    if uri then
      local range = location.range or location.targetSelectionRange
      local start = range and range.start or { line = 0, character = 0 }
      local filename = vim.uri_to_fname(uri)
      local container = symbol.containerName and symbol.containerName ~= "" and " in " .. symbol.containerName or ""

      entries[#entries + 1] = {
        filename = filename,
        lnum = start.line + 1,
        col = byte_column(start, encoding, loaded[filename]),
        text = ("[%s] %s%s"):format(vim.lsp.protocol.SymbolKind[symbol.kind] or "Unknown", symbol.name, container),
      }
    end
  end

  return entries
end

local function backend(name, client_for)
  local self = { name = name, label = name, kinds = KINDS }

  function self.offer(ctx)
    local client, why = client_for(ctx)

    if not client then
      return nil, why
    end

    return "workspace symbols, " .. vim.fn.fnamemodify(client.root_dir or ctx.cwd, ":~")
  end

  function self.search(_, pattern, ctx, done)
    local client, why = client_for(ctx)

    if not client then
      return done(nil, ("%s: %s"):format(name, why), vim.log.levels.ERROR)
    end

    local sent, id = client:request(METHOD, { query = pattern }, function(err, result)
      if err then
        return done(nil, ("%s: %s"):format(client.name, err.message or tostring(err)), vim.log.levels.ERROR)
      end

      local entries, truncated = entries_of(result or {}, client.offset_encoding)

      if truncated then
        return done(entries, ("%s: only the first %d symbols"):format(client.name, #entries), vim.log.levels.WARN)
      end

      done(entries)
    end, ctx.buf)

    if not sent then
      return done(nil, client.name .. " did not take the request", vim.log.levels.ERROR)
    end

    return function()
      pcall(client.cancel_request, client, id)
    end
  end

  return self
end

-- The buffer's clangd, else (assembler, linker scripts) the one serving its tree; never an #if variant (clangd~N).
local function clangd(ctx)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = ctx.buf, name = "clangd" })) do
    if answers(client, ctx.buf) then
      return client
    end
  end

  for _, client in ipairs(vim.lsp.get_clients({ name = "clangd" })) do
    if client.root_dir and ctx.file and vim.fs.relpath(client.root_dir, ctx.file) and answers(client, ctx.buf) then
      return client
    end
  end

  return nil, "no clangd serves this buffer"
end

M.clangd = backend("clangd", clangd)

-- The attached servers that answer workspace/symbol, by name (buffers outside the C family).
function M.attached(ctx)
  local list, seen = {}, {}

  for _, client in ipairs(vim.lsp.get_clients({ bufnr = ctx.buf })) do
    local name = client.name

    if not seen[name] and answers(client, ctx.buf) then
      seen[name] = true
      list[#list + 1] = backend(name, function(c)
        local found = vim.lsp.get_clients({ bufnr = c.buf, name = name })[1]

        if not found then
          return nil, ("no language server named %s is attached"):format(name)
        end

        return found
      end)
    end
  end

  table.sort(list, function(a, b)
    return a.name < b.name
  end)

  return list
end

return M
