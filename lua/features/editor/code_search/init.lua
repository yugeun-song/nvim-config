-- Code search by a typed pattern (<leader>i/, :CodeSearch): tool, query kind, pattern, then the <leader>i picker.
local context = require("features.editor.code_search.buffer_context")
local search_job = require("features.editor.code_search.search_job")

local M = {}

local BACKENDS = "features.editor.code_search.backends."
local C_TOOLS = { "clangd", "cscope", "ctags", "gtags" }
local TEXT_TOOLS = { "rg", "fd" }
local MODULES = {
  cscope = "cscope",
  ctags = "ctags",
  gtags = "gtags",
  rg = "ripgrep",
  fd = "fd",
}

local function fixed(name)
  if name == "clangd" then
    return require(BACKENDS .. "language_server").clangd
  end

  return MODULES[name] and require(BACKENDS .. MODULES[name])
end

-- The tools this buffer supports, in the chooser's order, each with what it reads.
local function offers(ctx)
  local list = {}

  local function add(backend)
    local detail = backend.offer(ctx)

    if detail then
      list[#list + 1] = { backend = backend, detail = detail }
    end
  end

  if ctx.c_family then
    for _, name in ipairs(C_TOOLS) do
      add(fixed(name))
    end
  elseif ctx.file then
    for _, backend in ipairs(require(BACKENDS .. "language_server").attached(ctx)) do
      add(backend)
    end
  end

  for _, name in ipairs(TEXT_TOOLS) do
    add(fixed(name))
  end

  return list
end

-- The offer of the tool named name, else why this buffer has none.
local function offered(name, ctx)
  for _, offer in ipairs(offers(ctx)) do
    if offer.backend.name == name then
      return offer
    end
  end

  local backend = fixed(name)

  if not backend then
    return nil,
      ctx.c_family and "C-family buffers take clangd, cscope, ctags, gtags and rg (or fd)"
        or "no language server of that name is attached; rg (or fd) always searches"
  end

  if not vim.list_contains(TEXT_TOOLS, name) then
    if not ctx.file then
      return nil, "this buffer has no file; only rg (or fd) searches from the working directory"
    end

    if not ctx.c_family then
      return nil,
        ("it serves C, C++, CUDA, assembly and linker-script buffers, and this one is %s"):format(
          ctx.filetype ~= "" and ctx.filetype or "of no filetype"
        )
    end
  end

  local _, why = backend.offer(ctx)

  return nil, why
end

local function kind_named(backend, name)
  for _, kind in ipairs(backend.kinds) do
    if kind.name == name then
      return kind
    end
  end
end

local function kind_names(backend)
  return vim.tbl_map(function(kind)
    return kind.name
  end, backend.kinds)
end

local function search(offer, kind, pattern, ctx)
  local backend = offer.backend

  search_job.cancel()
  if backend.open then
    return backend.open(kind, pattern, ctx)
  end

  local title = ("%s %s %s"):format(backend.name, kind.name, pattern)

  search_job.run(title, function(done)
    return backend.search(kind, pattern, ctx, done)
  end, function(entries, message, level)
    if message then
      search_job.notify(message, level)
    end

    if entries and #entries > 0 then
      require("features.editor.code_search.results_picker").open(title, entries, pattern)
    elseif entries and not message then
      search_job.notify("No results for " .. title, vim.log.levels.WARN)
    end
  end)
end

local function ask_pattern(offer, kind, ctx)
  vim.ui.input({ prompt = ("%s %s: "):format(offer.backend.label, kind.label) }, function(input)
    local pattern = input and vim.trim(input) or ""

    if pattern ~= "" then
      search(offer, kind, pattern, ctx)
    end
  end)
end

local function choose_kind(offer, ctx)
  local kinds = offer.backend.kinds

  if #kinds == 1 then
    return ask_pattern(offer, kinds[1], ctx)
  end

  vim.ui.select(kinds, {
    prompt = offer.backend.label .. " query",
    format_item = function(kind)
      return ("%-10s %s"):format(kind.name, kind.label)
    end,
  }, function(kind)
    if kind then
      ask_pattern(offer, kind, ctx)
    end
  end)
end

function M.choose()
  local ctx = context.of()
  local list = offers(ctx)

  if #list == 0 then
    return search_job.notify("Nothing can search here: no rg, fd or language server", vim.log.levels.ERROR)
  end

  local width = 0

  for _, offer in ipairs(list) do
    width = math.max(width, #offer.backend.label)
  end

  vim.ui.select(list, {
    prompt = "Code search",
    format_item = function(offer)
      return ("%-" .. width .. "s  %s"):format(offer.backend.label, offer.detail)
    end,
  }, function(offer)
    if offer then
      choose_kind(offer, ctx)
    end
  end)
end

-- :CodeSearch [tool [kind [pattern]]]; the pattern is the rest of the line, as typed.
function M.command(args)
  local name, rest = args:match("^%s*(%S+)%s*(.-)%s*$")

  if not name then
    return M.choose()
  end

  local ctx = context.of()
  local offer, why = offered(name, ctx)

  if not offer then
    return search_job.notify(("%s cannot work here: %s"):format(name, why), vim.log.levels.ERROR)
  end

  local kind_name, pattern = rest:match("^(%S+)%s*(.-)$")

  if not kind_name then
    return choose_kind(offer, ctx)
  end

  local kind = kind_named(offer.backend, kind_name)

  if not kind then
    return search_job.notify(
      ("%s has no query %s; it takes %s"):format(name, kind_name, table.concat(kind_names(offer.backend), ", ")),
      vim.log.levels.ERROR
    )
  end

  if pattern == "" then
    return ask_pattern(offer, kind, ctx)
  end

  search(offer, kind, pattern, ctx)
end

function M.complete(lead, line, pos)
  local words = vim.split((line:sub(1, pos):gsub("^%s+", "")), "%s+")
  local ctx = context.of()
  local candidates = {}

  if #words == 2 then
    candidates = vim.tbl_map(function(offer)
      return offer.backend.name
    end, offers(ctx))
  elseif #words == 3 then
    local offer = offered(words[2], ctx)

    candidates = offer and kind_names(offer.backend) or {}
  end

  return vim.tbl_filter(function(candidate)
    return vim.startswith(candidate, lead)
  end, candidates)
end

function M.create_command()
  vim.api.nvim_create_user_command("CodeSearch", function(opts)
    M.command(opts.args)
  end, {
    nargs = "?",
    complete = M.complete,
    desc = "Search with a tool this buffer supports, without the cursor: CodeSearch [tool [kind [pattern]]]",
  })
end

-- :checkhealth features.editor: each tool, available or blocked.
function M.health()
  local status = require("features.util.feature_status")

  if status.plugin_installed("telescope.nvim") then
    status.available("Code search (<leader>i/, :CodeSearch)", "results in the <leader>i Telescope picker")
  else
    status.blocked("Code search (<leader>i/, :CodeSearch)", "telescope.nvim is not installed", { ":Lazy install" })
  end

  status.programs("clangd: workspace symbols in the C-family buffers it serves", { "clangd" })
  status.programs("cscope: :Cscope find with the nearest cscope.out", { "cscope" }, {
    status.WINDOWS and "cscope has no native Windows build: register one by path (<leader>uX)" or "install cscope",
  })

  status.available("ctags: Neovim's tag search over the tags files 'tags' finds")
  status.programs("gtags: global with the nearest GTAGS", { "global" }, { "install GNU Global; gtags builds GTAGS" })

  if status.find("rg") then
    status.available("ripgrep: text under the root <leader>/ greps", status.find("rg"))
  elseif status.find({ "fd", "fdfind" }) then
    status.available("fd: file names only, while rg is missing", status.find({ "fd", "fdfind" }))
  else
    status.blocked("ripgrep or fd", "neither rg nor fd is on PATH", { "install ripgrep" })
  end

  status.available("Language servers: workspace symbols from the attached ones, by name")
end

return M
