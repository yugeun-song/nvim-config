-- nvim -l scripts/update_readme_credits.lua --write|--check: the Credits section of README.md, from lazy-lock.json,
-- the installed plugins' LICENSE files, Mason's registry and the lists below.
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(arg[0], ":p"))))
local data = vim.fn.stdpath("data")
local START, STOP = "<!-- credits:start -->", "<!-- credits:end -->"

local PROGRAMS = {
  { "Neovim", "https://neovim.io", "Apache-2.0 and Vim", "the editor" },
  { "git", "https://git-scm.com", "GPL-2.0", "plugins, the statusline tag" },
  { "tree-sitter CLI", "https://github.com/tree-sitter/tree-sitter", "MIT", "parser builds" },
  { "ripgrep", "https://github.com/BurntSushi/ripgrep", "MIT or Unlicense", "grep" },
  { "fd", "https://github.com/sharkdp/fd", "MIT or Apache-2.0", "file search" },
  { "cscope", "https://cscope.sourceforge.net", "BSD-3-Clause", "symbol navigation" },
  { "Universal Ctags", "https://ctags.io", "GPL-2.0", "the `tags` file" },
  { "GDB", "https://www.gnu.org/software/gdb", "GPL-3.0", "the debug adapter" },
  { "LLDB", "https://lldb.llvm.org", "Apache-2.0 WITH LLVM-exception", "C and C++ on macOS (lldb-dap)" },
  { "QEMU", "https://www.qemu.org", "GPL-2.0, parts under other licenses", "user-mode and kernel targets" },
  { "SBCL", "https://www.sbcl.org", "public domain and BSD-style", "Common Lisp" },
  { "ocicl", "https://github.com/ocicl/ocicl", "MIT", "Lisp systems and lint" },
  { "alive-lsp", "https://github.com/nobody-famous/alive-lsp", "Unlicense", "the Common Lisp server" },
  { "Racket", "https://racket-lang.org", "MIT or Apache-2.0", "the Racket REPL and docs" },
  { "GHC, cabal, hlint", "https://www.haskell.org", "BSD-3-Clause", "Haskell" },
  {
    "haskell-language-server",
    "https://github.com/haskell/haskell-language-server",
    "Apache-2.0",
    "the Haskell server",
  },
  { "Lean 4", "https://lean-lang.org", "Apache-2.0", "Lean, through elan" },
  { "ruff", "https://github.com/astral-sh/ruff", "MIT", "Python lint and format" },
  { "fcitx5", "https://github.com/fcitx/fcitx5", "LGPL-2.1", "the IME switch and state" },
  { "yazi", "https://github.com/sxyazi/yazi", "MIT", "Open Folder" },
  { "Neovide", "https://neovide.dev", "MIT", "the GUI" },
  { "kitty", "https://sw.kovidgoyal.net/kitty", "GPL-3.0", "the terminal the profile is tuned for" },
  -- Proprietary programs, run where the user has them, under the terms the user accepted with them.
  {
    "Visual Studio, Build Tools (MSVC, MSBuild, vswhere)",
    "https://visualstudio.microsoft.com",
    "Microsoft Software License Terms (proprietary)",
    "the MSVC environment, compile databases, building native/windows_ime_helper.c (Windows)",
  },
  {
    "NVIDIA CUDA Toolkit",
    "https://developer.nvidia.com/cuda-toolkit",
    "NVIDIA CUDA Toolkit EULA (proprietary)",
    "its headers and nvcc's flags, read by clangd for CUDA files",
  },
  {
    "Windows PowerShell",
    "https://learn.microsoft.com/powershell",
    "part of Windows (proprietary)",
    "program discovery and a window-raise fallback (Windows)",
  },
  { "Discord", "https://discord.com", "Discord Terms of Service (proprietary)", "Rich Presence, optional" },
}

-- What the credits say about the licenses as a whole, and about names and marks.
local CLOSING = {
  "This repository holds none of these plugins', packages' or programs' code: lazy.nvim, Mason and the system",
  "install each from its own source under its own license, and the proprietary ones under the terms their users",
  "accept. The configuration's own files are under the BSD Zero Clause License (`LICENSE`), which every license",
  'above, the GPL included, can be combined with; the files and parts listed under "Code and assets taken into',
  'this repository" keep their own licenses (`THIRD-PARTY-NOTICES`).',
  "",
  "Product names, logos and brands (Microsoft, Windows, Visual Studio, NVIDIA, CUDA, Discord, Apple, macOS,",
  "Linux distributions and the rest) belong to their owners; they are named here and drawn in the dashboard",
  "only to say what works with what. This project is not affiliated with, sponsored or endorsed by any of them.",
}

local ADAPTED = {
  "[LazyVim starter](https://github.com/LazyVim/starter) (Apache-2.0): `init.lua`, `lua/config/lazy.lua`, `stylua.toml`.",
  "[LazyVim](https://github.com/LazyVim/LazyVim) (Apache-2.0): parts of `lua/config/autocmds.lua` and `lua/plugins/debugging/other_language_debuggers.lua`.",
  "[spaceduck](https://github.com/pineapplegiant/spaceduck) by Guillermo Rodriguez (MIT): the palette and terminal colours of `colors/spaceduck-remix.lua`, an unofficial derivative.",
  "[nvim-hlslens](https://github.com/kevinhwang91/nvim-hlslens) by kevinhwang91 (BSD-3-Clause): the lens override and search keys in `lua/plugins/appearance/search_match_count.lua`.",
  "[kanagawa.nvim](https://github.com/rebelot/kanagawa.nvim) by Tommaso Laurenzi (MIT): the float and gutter recipes in `lua/plugins/appearance/colorscheme.lua`.",
  "[fastfetch](https://github.com/fastfetch-cli/fastfetch) (MIT): the system logos in `lua/features/appearance/dashboard_header.lua`.",
  "[Simple Icons](https://simpleicons.org) (CC0-1.0): the logos' brand colours.",
  "[presence.nvim](https://github.com/andweeb/presence.nvim) by andweeb: the public Discord application ID and its `neovim` art.",
}

local function read(path)
  local fd = io.open(path, "rb")

  if not fd then
    return nil
  end

  local text = fd:read("*a")

  fd:close()

  return text
end

local function license_of(dir)
  for name, kind in vim.fs.dir(dir) do
    local lower = name:lower()

    if kind == "file" and (lower:find("^licen[cs]e") or lower:find("^copying") or lower:find("^unlicense")) then
      local text = read(vim.fs.joinpath(dir, name)) or ""
      local spdx = text:find("Apache License", 1, true) and "Apache-2.0"
        or text:find("GNU LESSER GENERAL PUBLIC LICENSE", 1, true) and "LGPL"
        or text:find("GNU GENERAL PUBLIC LICENSE", 1, true) and (text:find("Version 3", 1, true) and "GPL-3.0" or "GPL-2.0")
        or text:find("Mozilla Public License", 1, true) and "MPL-2.0"
        or text:find("Neither the name", 1, true) and "BSD-3-Clause"
        or text:find("Redistribution and use", 1, true) and "BSD-2-Clause"
        or text:find("Permission is hereby granted, free of charge", 1, true) and "MIT"
        or text:find("free and unencumbered software", 1, true) and "Unlicense"
        or "see " .. name

      local holder

      for line in text:gmatch("[^\n]+") do
        local rest = line:match("^%s*Copyright%s+(.*)")

        if
          rest
          and not rest:find("Free Software Foundation", 1, true)
          and not rest:find("[%[{]")
          and not rest:find("<year>", 1, true)
        then
          rest = rest:gsub("^%(?[cC]%)?%s*", ""):gsub("[%d%s,%-]+", " ", 1):gsub("<.->", "")
          rest = vim.trim(rest:gsub("[Aa]ll rights reserved%.?", ""):gsub("[,%s]+$", ""))
          if rest ~= "" then
            holder = rest
            break
          end
        end
      end

      return spdx, holder
    end
  end

  return "unknown", nil
end

local function origin(dir)
  local res = vim.system({ "git", "-C", dir, "remote", "get-url", "origin" }, { text = true }):wait(5000)
  local url = vim.trim(res.stdout or ""):gsub("%.git$", ""):gsub("^git@github%.com:", "https://github.com/")

  return url ~= "" and url or nil, url:match("github%.com/([^/]+)/")
end

local function sorted(list)
  table.sort(list, function(a, b)
    return a:lower() < b:lower()
  end)

  return list
end

local function plugin_rows()
  local lock = vim.json.decode(assert(read(vim.fs.joinpath(root, "lazy-lock.json"))))
  local rows = {}

  for _, name in ipairs(sorted(vim.tbl_keys(lock))) do
    local dir = vim.fs.joinpath(data, "lazy", name)

    if vim.fn.isdirectory(dir) == 0 then
      return nil, name .. " is not installed"
    end

    local url, owner = origin(dir)
    local spdx, holder = license_of(dir)
    local title = url and ("[%s](%s)"):format(name, url) or name

    rows[#rows + 1] = ("| %s | %s | %s |"):format(title, holder or owner or "", spdx)
  end

  return rows
end

local function mason_names()
  local spec = dofile(vim.fs.joinpath(root, "lua", "plugins", "external_programs", "mason_packages.lua"))
  local names = vim.deepcopy(spec.opts.ensure_installed)
  local lazyvim = read(vim.fs.joinpath(data, "lazy", "LazyVim", "lua", "lazyvim", "plugins", "lsp", "init.lua")) or ""
  local at = lazyvim:find('"mason-org/mason.nvim"', 1, true)
  local list = at and lazyvim:match("ensure_installed%s*=%s*(%b{})", at)

  for name in (list or ""):gmatch('"([^"]+)"') do
    if not vim.list_contains(names, name) then
      names[#names + 1] = name
    end
  end

  return sorted(names)
end

local function mason_rows()
  local path = vim.fs.joinpath(data, "mason", "registries", "github", "mason-org", "mason-registry", "registry.json")
  local text = read(path)

  if not text then
    return nil, "the Mason registry is not downloaded"
  end

  local registry = {}

  for _, entry in ipairs(vim.json.decode(text)) do
    registry[entry.name] = entry
  end

  local rows = {}

  for _, name in ipairs(mason_names()) do
    local entry = registry[name] or {}
    local title = entry.homepage and ("[%s](%s)"):format(name, entry.homepage) or name

    rows[#rows + 1] = ("| %s | %s |"):format(title, table.concat(entry.licenses or { "unknown" }, " / "))
  end

  return rows
end

local function section()
  local plugins, why = plugin_rows()

  if not plugins then
    return nil, why
  end

  local mason, mwhy = mason_rows()

  if not mason then
    return nil, mwhy
  end

  local out = {
    START,
    "",
    "Code and assets taken into this repository (notices in `THIRD-PARTY-NOTICES`):",
    "",
  }

  for _, line in ipairs(ADAPTED) do
    out[#out + 1] = "- " .. line
  end

  vim.list_extend(out, { "", "Plugins (`lazy-lock.json`; author from the LICENSE, else the repository owner):", "" })
  vim.list_extend(out, { "| Plugin | Author | License |", "|---|---|---|" })
  vim.list_extend(out, plugins)
  vim.list_extend(
    out,
    { "", "Mason packages (`lua/plugins/external_programs/mason_packages.lua` and LazyVim's defaults):", "" }
  )

  vim.list_extend(out, { "| Package | License |", "|---|---|" })
  vim.list_extend(out, mason)
  vim.list_extend(out, { "", "Programs it runs:", "", "| Program | License | Used for |", "|---|---|---|" })
  for _, p in ipairs(PROGRAMS) do
    out[#out + 1] = ("| [%s](%s) | %s | %s |"):format(p[1], p[2], p[3], p[4])
  end

  out[#out + 1] = ""
  vim.list_extend(out, CLOSING)

  vim.list_extend(out, { "", STOP })

  return table.concat(out, "\n")
end

local readme_path = vim.fs.joinpath(root, "README.md")
local readme = assert(read(readme_path))
local s, e = readme:find(START, 1, true), select(2, readme:find(STOP, 1, true))

if not (s and e) then
  io.stderr:write("README.md has no " .. START .. " ... " .. STOP .. " block\n")
  vim.cmd.cquit(1)
end

local block, why = section()

if not block then
  io.stdout:write("skipped: " .. why .. "\n")

  return
end

local updated = readme:sub(1, s - 1) .. block .. readme:sub(e + 1)

if arg[1] == "--write" then
  if updated ~= readme then
    local fd = assert(io.open(readme_path, "wb"))

    fd:write(updated)
    fd:close()
  end
elseif updated ~= readme then
  io.stdout:write("README.md Credits is out of date: run nvim -l scripts/update_readme_credits.lua --write\n")
  vim.cmd.cquit(1)
end
