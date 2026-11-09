-- CUDA (.cu, .cuh) in clang's CUDA mode in clangd, on every system (lua/features/lang/cuda.lua). Nothing here
-- runs for C or C++ files.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "cuda" } },
  },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local cuda = require("features.lang.cuda")

      opts.servers = opts.servers or {}
      opts.servers.clangd = vim.tbl_deep_extend("force", opts.servers.clangd or {}, {
        -- Two diagnostics clang gives where nvcc compiles are dropped from .cu and .cuh files; everything else
        -- passes through untouched.
        handlers = {
          ["textDocument/publishDiagnostics"] = function(err, params, ctx)
            local uri = params and params.uri or ""

            if uri:sub(-3):lower() == ".cu" or uri:sub(-4):lower() == ".cuh" then
              params = cuda.filter(params)
            end

            return (vim.lsp.handlers["textDocument/publishDiagnostics"] or vim.lsp.diagnostic.on_publish_diagnostics)(
              err,
              params,
              ctx
            )
          end,
        },
      })

      local fallback = cuda.fallback_flags()

      if fallback then
        opts.servers.clangd.init_options =
          vim.tbl_deep_extend("force", opts.servers.clangd.init_options or {}, { fallbackFlags = fallback })
      end

      -- A CUDA buffer whose compile command is nvcc's gets clang's instead.
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("clangd_for_cuda", { clear = true }),
        callback = function(ev)
          local client = vim.lsp.get_client_by_id(ev.data.client_id)

          if client and client.name == "clangd" and vim.bo[ev.buf].filetype == "cuda" then
            cuda.attach(client, ev.buf)
          end
        end,
      })
    end,
  },
}
