local function private_tmp()
  local base = require("features.maintenance.local_storage").path("cache", "clangd_temporary_files")

  for name in vim.fs.dir(base) do
    local pid = tonumber(name)

    if pid and pid ~= vim.fn.getpid() and vim.uv.kill(pid, 0) ~= 0 then
      pcall(vim.fs.rm, vim.fs.joinpath(base, name), { recursive = true, force = true })
    end
  end

  local dir = vim.fs.joinpath(base, tostring(vim.fn.getpid()))

  ---@diagnostic disable-next-line: param-type-mismatch
  vim.fn.mkdir(dir, "p", tonumber("700", 8))
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("clangd_tmp", { clear = true }),
    callback = function()
      pcall(vim.fs.rm, dir, { recursive = true, force = true })
    end,
  })

  return dir
end

-- Windows: clangd assumes an MSVC target and its headers. A compile database written for MinGW's gcc (or a
-- clang on PATH) needs clangd to ask that compiler for its target and system includes, which it does only for
-- drivers in this allowlist: the directories the compilers on PATH live in, so nothing a repository names runs.
local function query_driver()
  local dirs, seen = {}, {}
  -- PATH's own entries only: with cmd.exe as 'shell', exepath() also finds a compiler in the current directory,
  -- which a repository could put there.
  local on_path = {}

  for entry in (vim.env.PATH or ""):gmatch("[^;]+") do
    local dir = vim.fs.normalize(entry):gsub("/+$", "")

    if vim.fn.isabsolutepath(dir) == 1 then
      on_path[dir:lower()] = true
    end
  end

  for _, name in ipairs({ "gcc", "g++", "cc", "c++", "clang", "clang++" }) do
    local path = vim.fn.exepath(name)

    if path ~= "" then
      local dir = vim.fs.dirname(vim.fs.normalize(path))

      if on_path[dir:lower()] and not seen[dir:lower()] then
        seen[dir:lower()] = true
        dirs[#dirs + 1] = dir .. "/*"
      end
    end
  end

  return #dirs > 0 and ("--query-driver=" .. table.concat(dirs, ",")) or nil
end

return {
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    local tmp = private_tmp()

    opts.servers = opts.servers or {}
    opts.servers.clangd = {
      cmd = {
        "clangd",
        "--background-index",
        "--clang-tidy",
        "--completion-style=detailed",
        "--header-insertion=never",
        -- Preambles on disk: a kernel preamble is 10-15 MB per open file, and seven
        -- trees open at once filled a 16 GB machine.
        "--pch-storage=disk",
        -- Unindexed trees yield to editing; an index built ahead of time skips the wait.
        "--background-index-priority=background",
        -- Bound the answers that can blow up on kernel-sized symbol sets.
        "--limit-results=200",
        "--limit-references=2000",
        -- Neovim logs server stderr at ERROR; clangd's info lines grew lsp.log past 100 MB.
        "--log=error",
        "-j=" .. vim.uv.available_parallelism(),
      },
      cmd_env = { TMPDIR = tmp, TMP = tmp, TEMP = tmp },
      -- CUDA (lua/features/languages/cuda/clangd_for_cuda.lua): two diagnostics clang gives where nvcc compiles are
      -- dropped from .cu and .cuh files; everything else passes through untouched.
      handlers = {
        ["textDocument/publishDiagnostics"] = function(err, params, ctx)
          local uri = params and params.uri or ""

          if uri:sub(-3):lower() == ".cu" or uri:sub(-4):lower() == ".cuh" then
            params = require("features.languages.cuda.clangd_for_cuda").filter(params)
          end

          return (vim.lsp.handlers["textDocument/publishDiagnostics"] or vim.lsp.diagnostic.on_publish_diagnostics)(
            err,
            params,
            ctx
          )
        end,
      },
    }

    local cuda = require("features.languages.cuda.clangd_for_cuda")
    local fallback = cuda.fallback_flags()

    if fallback then
      opts.servers.clangd.init_options = { fallbackFlags = fallback }
    end

    -- A CUDA buffer whose compile command is nvcc's gets clang's instead.
    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("cuda_clangd", { clear = true }),
      callback = function(ev)
        local client = vim.lsp.get_client_by_id(ev.data.client_id)

        if client and client.name == "clangd" and vim.bo[ev.buf].filetype == "cuda" then
          cuda.attach(client, ev.buf)
        end
      end,
    })

    local asm_navigation = require("features.languages.assembly.definition_navigation")

    opts.servers[asm_navigation.CLIENT] = asm_navigation.server()

    if vim.fn.has("win32") == 1 then
      local flag = query_driver()

      if flag then
        table.insert(opts.servers.clangd.cmd, flag)
        table.insert(opts.servers[asm_navigation.CLIENT].cmd, flag)
      end
    end
  end,
}
