-- Language servers serve buffers with a file only. Neovim starts a server for any buffer of its filetype, and one
-- without a name (:enew, then a filetype) reaches it as the URI "file://", which no server can read: clangd answered
-- every request with "unresolvable URI", ruff panicked. vim.lsp.start(), which every server goes through (those
-- vim.lsp.enable() starts, rustaceanvim's, haskell-tools'), starts and attaches nothing to such a buffer, and a server
-- attached to one by other means leaves it at once. Once the buffer has a name (:w name, :file, :saveas), the servers
-- enabled for its filetype start, as they would have at FileType. No server's config is rewritten, so Neovim keeps the
-- ones it resolved.
local M = {}

local function nameless(bufnr)
  return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == "" and vim.bo[bufnr].buftype == ""
end

-- Buffers that got a filetype while they had no name: their servers start once they have one.
local waiting = {}

local installed = false

-- Installed once, before any server starts (lua/plugins/lsp/file_buffers.lua).
function M.install()
  if installed then
    return
  end

  installed = true

  local start = vim.lsp.start

  ---@diagnostic disable-next-line: duplicate-set-field
  vim.lsp.start = function(config, opts)
    local bufnr = opts and opts.bufnr or 0

    bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

    if not (opts and opts.attach == false) and nameless(bufnr) then
      -- Also when the servers were enabled after its FileType (nvim-lspconfig loads at the first file event).
      waiting[bufnr] = true

      return nil
    end

    return start(config, opts)
  end

  local group = vim.api.nvim_create_augroup("lsp_file_buffers", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(ev)
      waiting[ev.buf] = nameless(ev.buf) or nil
    end,
  })

  -- vim.lsp.enable() starts servers from a FileType autocmd matched by filetype: run in the buffer, for its filetype,
  -- after the write has finished.
  vim.api.nvim_create_autocmd({ "BufFilePost", "BufWritePost" }, {
    group = group,
    callback = function(ev)
      if not waiting[ev.buf] or nameless(ev.buf) then
        return
      end

      waiting[ev.buf] = nil

      local buf = ev.buf

      vim.schedule(function()
        local filetype = vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype or ""

        if filetype ~= "" then
          vim.api.nvim_buf_call(buf, function()
            pcall(vim.api.nvim_exec_autocmds, "FileType", {
              group = "nvim.lsp.enable",
              pattern = filetype,
              modeline = false,
            })
          end)
        end
      end)
    end,
    desc = "Start the language servers of a buffer that got a name",
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    -- :w name gives a buffer without a name that name, and Neovim sends a BufWipeout for it on the way: only a buffer
    -- that is really gone is forgotten.
    callback = function(ev)
      local buf = ev.buf

      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          waiting[buf] = nil
        end
      end)
    end,
  })

  -- A server attached by other means than vim.lsp.start() (vim.lsp.buf_attach_client()) leaves such a buffer.
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      if not nameless(ev.buf) then
        return
      end

      local id = ev.data.client_id

      vim.schedule(function()
        local client = vim.lsp.get_client_by_id(id)

        if client and nameless(ev.buf) then
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

return M
