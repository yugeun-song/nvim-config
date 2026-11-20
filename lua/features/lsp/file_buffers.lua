-- Language servers serve buffers with a file only. Neovim starts a server for any buffer of its filetype, and one
-- without a name (:enew, then a filetype) reaches it as the URI "file://", which no server can read: clangd answers
-- every request with "unresolvable URI", ruff panicked. A gate comes before every server's root_dir, so nothing is
-- started and nothing is sent.
--
-- The last vim.lsp.config() of a server wins, and its root_dir comes from its spec, nvim-lspconfig's lsp/<name>.lua or
-- mason-lspconfig, which sets its own just before enabling a server it installed. So the gate is given to the specs'
-- root_dir before anything is enabled, to every enabled server by name once nvim-lspconfig has set them up, and again
-- after each Mason install; a server that still reaches such a buffer (enabled while one was open) leaves it at once.
-- Never through "*": rustaceanvim merges it into its own rust-analyzer config and calls root_dir(file_name, default).
local M = {}

---@alias features.lsp.RootDir string|fun(bufnr: integer, on_dir: fun(root_dir?: string))

-- The gates made here: a root_dir already gated is not wrapped again.
local gates = setmetatable({}, { __mode = "k" })

local function has_file(bufnr)
  return vim.api.nvim_buf_get_name(bufnr) ~= ""
end

-- The root_dir of a server with none of its own: its root_markers decide, as Neovim does without a root_dir.
function M.root_dir(bufnr, on_dir)
  if has_file(bufnr) then
    on_dir(nil)
  end
end

gates[M.root_dir] = true

-- A server's own root_dir, a function or a fixed directory, behind the gate.
---@param root_dir features.lsp.RootDir
function M.guard(root_dir)
  if gates[root_dir] then
    return root_dir
  end

  local gate = function(bufnr, on_dir)
    if not has_file(bufnr) then
      return
    end

    if type(root_dir) == "function" then
      return root_dir(bufnr, on_dir)
    end

    on_dir(root_dir)
  end

  gates[gate] = true

  return gate
end

-- The root_dir a server ends up with, or nil; never raises for a broken config (vim.lsp.enable reports those).
---@return features.lsp.RootDir?
local function resolved_root_dir(name)
  local ok, config = pcall(function()
    return vim.lsp.config[name]
  end)

  return ok and config and config.root_dir or nil
end

-- Gives the gate to one server through vim.lsp.config, unless it is gated already: its own root_dir behind it, else
-- M.root_dir, which leaves the root to its root_markers.
local function gate_config(name)
  local own = resolved_root_dir(name)

  if not gates[own] then
    vim.lsp.config(name, { root_dir = own ~= nil and M.guard(own) or M.root_dir })
  end
end

-- Every enabled server, after nvim-lspconfig and mason-lspconfig have set them up.
function M.gate_enabled()
  for _, config in ipairs(vim.lsp.get_configs({ enabled = true })) do
    gate_config(config.name)
  end
end

local watching = false

-- Watches for the servers enabled after this: nvim-lspconfig's setup, and Mason installs later in the session.
local function watch()
  if watching then
    return
  end

  watching = true

  local group = vim.api.nvim_create_augroup("lsp_file_buffers", { clear = true })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "LazyLoad",
    callback = function(ev)
      if ev.data ~= "nvim-lspconfig" then
        return
      end

      M.gate_enabled()

      local ok, registry = pcall(require, "mason-registry")

      if ok then
        -- Mason calls its handlers in no set order, so mason-lspconfig may enable the new server before or after
        -- this; the LspAttach check below covers a buffer it reaches first.
        registry:on("package:install:success", vim.schedule_wrap(M.gate_enabled))
      end

      return true
    end,
    desc = "No language server for a buffer without a file: gate the servers nvim-lspconfig enabled",
  })

  -- Last resort, for a server enabled before its gate (a Mason install mid-session): it leaves such a buffer at once.
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      if has_file(ev.buf) or vim.bo[ev.buf].buftype ~= "" then
        return
      end

      local id = ev.data.client_id

      vim.schedule(function()
        local client = vim.lsp.get_client_by_id(id)

        if client and vim.api.nvim_buf_is_valid(ev.buf) and not has_file(ev.buf) then
          pcall(vim.lsp.buf_detach_client, ev.buf, id)

          if next(client.attached_buffers) == nil then
            client:stop()
          end
        end
      end)
    end,
    desc = "No language server for a buffer without a file: detach one that reached it",
  })
end

-- LazyVim's opts.servers, before anything is enabled: a root_dir a spec sets. Resolving the others here would read
-- every server's lsp/<name>.lua ahead of Neovim (about 35 ms at the first file); gate_enabled() resolves only the
-- enabled ones, which Neovim then keeps.
function M.apply(servers)
  for name, server in pairs(servers) do
    if name ~= "*" and type(server) == "table" and server.enabled ~= false and server.root_dir ~= nil then
      server.root_dir = M.guard(server.root_dir)
    end
  end

  watch()
end

return M
