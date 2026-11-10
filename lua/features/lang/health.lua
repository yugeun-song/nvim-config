-- :checkhealth features.lang. Tree-sitter parsers are the ones the merged configuration asks for.
local status = require("features.util.feature_status")

local M = {}

local function c_family()
  vim.health.start("C, C++, CUDA and assembly")
  status.programs("C and C++ language server", { "clangd" }, { ":MasonInstall clangd" })

  if status.find("clangd") then
    status.available("All #if branches (<leader>uB)", "clangd's inactive regions")
  else
    status.blocked("All #if branches (<leader>uB)", "needs clangd")
  end

  status.programs("C and C++ navigation", { "cscope", "ctags" })

  local cuda = require("features.lang.cuda").toolkit()

  if cuda then
    status.available("CUDA in clangd", cuda .. "; an nvcc compile command is read as clang's")
  else
    status.blocked("CUDA in clangd", "no toolkit in CUDA_PATH or beside nvcc; clangd looks only in its own places", {
      "install the CUDA toolkit, or set CUDA_PATH",
    })
  end

  if status.parser("asm") then
    status.available("Assembly highlighting, inline asm and PTX in C/C++/CUDA, gd in assembler")
  else
    status.blocked("Assembly highlighting", "no tree-sitter parser for asm", { ":TSInstall asm" })
  end

  if not status.WINDOWS then
    status.unsupported("MSVC environment and Visual Studio compile databases", "they are Visual Studio's")

    return
  end

  local msvc = require("features.lang.c.msvc_toolchain.developer_environment").read()
  local tools_dir = vim.env.VCToolsInstallDir

  if msvc and msvc.off then
    vim.health.info("MSVC environment: off (<leader>uX turns it on)")
  elseif tools_dir and tools_dir ~= "" then
    status.available("MSVC environment", ("%s, cl %s"):format(tools_dir, vim.fn.exepath("cl")))
  elseif msvc and msvc.none then
    status.blocked("MSVC environment", "no Visual Studio with the MSVC tools (C++ desktop workload) found")
  else
    status.blocked("MSVC environment", "not captured yet; it is, in the background, at the next start")
  end

  local msbuild = require("features.lang.c.msvc_toolchain.compile_database").msbuild_location()

  if msbuild then
    status.available("Visual Studio compile databases (:MsvcCompileDb)", msbuild)
  else
    status.blocked("Visual Studio compile databases (:MsvcCompileDb)", "no MSBuild found through vswhere")
  end
end

local function other_languages()
  vim.health.start("Other languages")
  status.programs("Common Lisp REPL", { "sbcl" })

  local alive_lsp = require("features.lang.lisp.alive_lsp")
  local server = "Common Lisp language server (alive-lsp)"

  if alive_lsp.ready() then
    status.available(server, alive_lsp.directory())
  elseif not status.find("sbcl") then
    status.blocked(server, "missing sbcl")
  else
    status.blocked(server, "no ocicl.csv in " .. alive_lsp.directory(), { "docs/features/lang.md#common-lisp" })
  end

  status.programs("Common Lisp lint", { "ocicl" })
  status.programs("Racket REPL", { "racket" })
  require("features.lang.haskell").add_to_path()
  status.programs(
    "Haskell",
    { "ghc", "cabal", { "haskell-language-server-wrapper", "haskell-language-server" } },
    { "https://www.haskell.org/ghcup/" }
  )

  status.programs("Haskell lint", { "hlint" }, { "https://github.com/ndmitchell/hlint" })
  status.programs("Lean 4", { "elan" }, { "https://github.com/leanprover/elan" })
  status.programs("Python lint and format", { "ruff" })
end

local function parsers()
  vim.health.start("Tree-sitter parsers")

  local wanted = status.plugin_options("nvim-treesitter").ensure_installed or {}
  local seen, missing = {}, {}

  for _, lang in ipairs(type(wanted) == "table" and wanted or {}) do
    if not seen[lang] then
      seen[lang] = true
      if not status.parser(lang) then
        missing[#missing + 1] = lang
      end
    end
  end

  table.sort(missing)
  if #missing == 0 then
    status.available(("all %d the configuration asks for"):format(vim.tbl_count(seen)))
  else
    status.blocked(("%d not installed"):format(#missing), table.concat(missing, ", "), {
      ":TSInstall " .. table.concat(missing, " "),
    })
  end

  status.programs("Parser builds", { "tree-sitter", { "cc", "gcc", "clang", "cl" }, "curl", "tar" })
end

function M.check()
  c_family()
  other_languages()
  parsers()
end

return M
