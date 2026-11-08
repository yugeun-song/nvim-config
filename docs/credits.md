# Credits

The configuration's own files are 0BSD ([`LICENSE`](../LICENSE)); files taken from other projects keep their licenses ([`THIRD-PARTY-NOTICES`](../THIRD-PARTY-NOTICES)). Everything between the markers below is written by `nvim -l scripts/update_credits.lua --write` ([development](development.md#credits)); edit the lists in that script, not this file.

<!-- credits:start -->

Code and assets taken into this repository (notices in `THIRD-PARTY-NOTICES`):

- [LazyVim starter](https://github.com/LazyVim/starter) (Apache-2.0): `init.lua`, `lua/config/lazy.lua`, `stylua.toml`.
- [LazyVim](https://github.com/LazyVim/LazyVim) (Apache-2.0): parts of `lua/config/autocmds.lua` and `lua/plugins/debugging/other_language_debuggers.lua`.
- [spaceduck](https://github.com/pineapplegiant/spaceduck) by Guillermo Rodriguez (MIT): the palette and terminal colours of `colors/spaceduck-remix.lua`, an unofficial derivative.
- [nvim-hlslens](https://github.com/kevinhwang91/nvim-hlslens) by kevinhwang91 (BSD-3-Clause): the lens override and search keys in `lua/plugins/appearance/search_match_count.lua`.
- [kanagawa.nvim](https://github.com/rebelot/kanagawa.nvim) by Tommaso Laurenzi (MIT): the float and gutter recipes in `lua/plugins/appearance/colorscheme.lua`.
- [fastfetch](https://github.com/fastfetch-cli/fastfetch) (MIT): the system logos in `lua/features/appearance/dashboard_header.lua`.
- [Simple Icons](https://simpleicons.org) (CC0-1.0): the logos' brand colours.
- [presence.nvim](https://github.com/andweeb/presence.nvim) by andweeb: the public Discord application ID and its `neovim` art.

Plugins (`lazy-lock.json`; author from the LICENSE, else the repository owner):

| Plugin | Author | License |
|---|---|---|
| [baleia.nvim](https://github.com/m00qek/baleia.nvim) | António Mora | MIT |
| [blink.cmp](https://github.com/saghen/blink.cmp) | Liam Dyer | MIT |
| [bufferline.nvim](https://github.com/akinsho/bufferline.nvim) | akinsho | GPL-3.0 |
| [catppuccin](https://github.com/catppuccin/nvim) | Catppuccin | MIT |
| [conform.nvim](https://github.com/stevearc/conform.nvim) | Steven Arcangeli | MIT |
| [cscope_maps.nvim](https://github.com/dhananjaylatkar/cscope_maps.nvim) | Dhananjay | MIT |
| [flash.nvim](https://github.com/folke/flash.nvim) | folke | Apache-2.0 |
| [friendly-snippets](https://github.com/rafamadriz/friendly-snippets) | Rafael Madriz | MIT |
| [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) | Lewis Russell | MIT |
| [grug-far.nvim](https://github.com/MagicDuck/grug-far.nvim) | Stephan Badragan | MIT |
| [gruvbox-material](https://github.com/sainnhe/gruvbox-material) | sainnhe | MIT |
| [haskell-tools.nvim](https://github.com/mrcjkb/haskell-tools.nvim) | mrcjkb | GPL-2.0 |
| [kanagawa.nvim](https://github.com/rebelot/kanagawa.nvim) | Tommaso Laurenzi | MIT |
| [lazy.nvim](https://github.com/folke/lazy.nvim) | folke | Apache-2.0 |
| [lazydev.nvim](https://github.com/folke/lazydev.nvim) | folke | Apache-2.0 |
| [LazyVim](https://github.com/LazyVim/LazyVim) | LazyVim | Apache-2.0 |
| [lean.nvim](https://github.com/Julian/lean.nvim) | Julian Berman | MIT |
| [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) | hoob3rt | MIT |
| [markview.nvim](https://github.com/OXY2DEV/markview.nvim) | OXY2DEV | Apache-2.0 |
| [mason-lspconfig.nvim](https://github.com/mason-org/mason-lspconfig.nvim) | mason-org | Apache-2.0 |
| [mason.nvim](https://github.com/mason-org/mason.nvim) | mason-org | Apache-2.0 |
| [mini.ai](https://github.com/nvim-mini/mini.ai) | Evgeni Chasnovski | MIT |
| [mini.files](https://github.com/nvim-mini/mini.files) | Evgeni Chasnovski | MIT |
| [mini.icons](https://github.com/nvim-mini/mini.icons) | Evgeni Chasnovski | MIT |
| [mini.pairs](https://github.com/nvim-mini/mini.pairs) | Evgeni Chasnovski | MIT |
| [neov-ime.nvim](https://github.com/sevenc-nanashi/neov-ime.nvim) | Nanashi. | MIT |
| [noice.nvim](https://github.com/folke/noice.nvim) | folke | Apache-2.0 |
| [nui.nvim](https://github.com/MunifTanjim/nui.nvim) | Munif Tanjim | MIT |
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | mfussenegger | GPL-3.0 |
| [nvim-dap-disasm](https://codeberg.org/Jorenar/nvim-dap-disasm) | Jorenar | MIT |
| [nvim-dap-python](https://github.com/mfussenegger/nvim-dap-python) | mfussenegger | GPL-3.0 |
| [nvim-dap-view](https://github.com/igorlfs/nvim-dap-view) | igorlfs | GPL-3.0 |
| [nvim-hlslens](https://github.com/kevinhwang91/nvim-hlslens) | kevinhwang91 | BSD-3-Clause |
| [nvim-lint](https://github.com/mfussenegger/nvim-lint) | mfussenegger | GPL-3.0 |
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | neovim | Apache-2.0 |
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | nvim-treesitter | Apache-2.0 |
| [nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects) | nvim-treesitter | Apache-2.0 |
| [nvim-ts-autotag](https://github.com/windwp/nvim-ts-autotag) | windwp | MIT |
| [persistence.nvim](https://github.com/folke/persistence.nvim) | folke | Apache-2.0 |
| [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) | TJ DeVries | MIT |
| [rustaceanvim](https://github.com/mrcjkb/rustaceanvim) | mrcjkb | GPL-2.0 |
| [snacks.nvim](https://github.com/folke/snacks.nvim) | folke | Apache-2.0 |
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | nvim-telescope | MIT |
| [todo-comments.nvim](https://github.com/folke/todo-comments.nvim) | folke | Apache-2.0 |
| [tokyonight.nvim](https://github.com/folke/tokyonight.nvim) | folke | Apache-2.0 |
| [trouble.nvim](https://github.com/folke/trouble.nvim) | folke | Apache-2.0 |
| [ts-comments.nvim](https://github.com/folke/ts-comments.nvim) | folke | Apache-2.0 |
| [which-key.nvim](https://github.com/folke/which-key.nvim) | folke | Apache-2.0 |

Mason packages (`lua/plugins/external_programs/mason_packages.lua` and LazyVim's defaults):

| Package | License |
|---|---|
| [awk-language-server](https://github.com/Beaglefoot/awk-language-server) | MIT |
| [bash-language-server](https://github.com/bash-lsp/bash-language-server) | MIT |
| [clang-format](https://pypi.org/project/clang-format/) | Apache-2.0 |
| [clangd](https://clangd.llvm.org) | Apache-2.0 |
| [codelldb](https://github.com/vadimcn/vscode-lldb) | MIT |
| [css-lsp](https://github.com/microsoft/vscode-css-languageservice) | MIT |
| [debugpy](https://github.com/microsoft/debugpy) | MIT |
| [detekt](https://detekt.dev/) | Apache-2.0 |
| [docker-language-server](https://github.com/docker/docker-language-server) | Apache-2.0 |
| [elixir-ls](https://github.com/elixir-lsp/elixir-ls) | Apache-2.0 |
| [elp](https://github.com/WhatsApp/erlang-language-platform) | Apache-2.0 / MIT |
| [expert](https://github.com/elixir-lang/expert) | Apache-2.0 |
| [html-lsp](https://github.com/microsoft/vscode-html-languageservice) | MIT |
| [jdtls](https://github.com/eclipse/eclipse.jdt.ls) | EPL-2.0 |
| [js-debug-adapter](https://github.com/microsoft/vscode-js-debug) | MIT |
| [json-lsp](https://github.com/microsoft/vscode-json-languageservice) | MIT |
| [julia-lsp](https://github.com/julia-vscode/LanguageServer.jl) | MIT |
| [kotlin-lsp](https://github.com/Kotlin/kotlin-lsp) | Apache-2.0 |
| [ktlint](https://github.com/pinterest/ktlint) | MIT |
| [lua-language-server](https://github.com/LuaLS/lua-language-server) | MIT |
| [oxfmt](https://oxc.rs/docs/guide/usage/formatter) | MIT |
| [oxlint](https://github.com/oxc-project/oxc) | MIT |
| [rumdl](https://github.com/rvben/rumdl) | MIT |
| [rust-analyzer](https://github.com/rust-lang/rust-analyzer) | Apache-2.0 / MIT |
| [shellcheck](https://www.shellcheck.net/) | GPL-3.0-or-later |
| [shfmt](https://github.com/mvdan/sh) | BSD-3-Clause |
| [stylua](https://github.com/JohnnyMorganz/StyLua) | MPL-2.0 |
| [taplo](https://taplo.tamasfe.dev/) | MIT |
| [ty](https://github.com/astral-sh/ty) | MIT |
| [vtsls](https://github.com/yioneko/vtsls) | MIT |
| [wasm-language-tools](https://github.com/g-plane/wasm-language-tools) | MIT |
| [yaml-language-server](https://github.com/redhat-developer/yaml-language-server) | MIT |
| [yamllint](https://github.com/adrienverge/yamllint) | GPL-3.0-or-later |

Programs it runs:

| Program | License | Used for |
|---|---|---|
| [Neovim](https://neovim.io) | Apache-2.0 and Vim | the editor |
| [git](https://git-scm.com) | GPL-2.0 | plugins, the statusline tag |
| [tree-sitter CLI](https://github.com/tree-sitter/tree-sitter) | MIT | parser builds |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | MIT or Unlicense | grep |
| [fd](https://github.com/sharkdp/fd) | MIT or Apache-2.0 | file search |
| [cscope](https://cscope.sourceforge.net) | BSD-3-Clause | symbol navigation |
| [Universal Ctags](https://ctags.io) | GPL-2.0 | the `tags` file |
| [GDB](https://www.gnu.org/software/gdb) | GPL-3.0 | the debug adapter |
| [LLDB](https://lldb.llvm.org) | Apache-2.0 WITH LLVM-exception | C and C++ on macOS (lldb-dap) |
| [QEMU](https://www.qemu.org) | GPL-2.0, parts under other licenses | user-mode and kernel targets |
| [SBCL](https://www.sbcl.org) | public domain and BSD-style | Common Lisp |
| [ocicl](https://github.com/ocicl/ocicl) | MIT | Lisp systems and lint |
| [alive-lsp](https://github.com/nobody-famous/alive-lsp) | Unlicense | the Common Lisp server |
| [Racket](https://racket-lang.org) | MIT or Apache-2.0 | the Racket REPL and docs |
| [GHC, cabal, hlint](https://www.haskell.org) | BSD-3-Clause | Haskell |
| [haskell-language-server](https://github.com/haskell/haskell-language-server) | Apache-2.0 | the Haskell server |
| [Lean 4](https://lean-lang.org) | Apache-2.0 | Lean, through elan |
| [ruff](https://github.com/astral-sh/ruff) | MIT | Python lint and format |
| [fcitx5](https://github.com/fcitx/fcitx5) | LGPL-2.1 | the IME switch and state |
| [yazi](https://github.com/sxyazi/yazi) | MIT | Open Folder |
| [Neovide](https://neovide.dev) | MIT | the GUI |
| [kitty](https://sw.kovidgoyal.net/kitty) | GPL-3.0 | the terminal the profile is tuned for |
| [Visual Studio, Build Tools (MSVC, MSBuild, vswhere)](https://visualstudio.microsoft.com) | Microsoft Software License Terms (proprietary) | the MSVC environment, compile databases, building native/windows_ime_helper.c (Windows) |
| [NVIDIA CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit) | NVIDIA CUDA Toolkit EULA (proprietary) | its headers and nvcc's flags, read by clangd for CUDA files |
| [Windows PowerShell](https://learn.microsoft.com/powershell) | part of Windows (proprietary) | program discovery and a window-raise fallback (Windows) |
| [Discord](https://discord.com) | Discord Terms of Service (proprietary) | Rich Presence, optional |

This repository holds none of these plugins', packages' or programs' code: lazy.nvim, Mason and the system
install each from its own source under its own license, and the proprietary ones under the terms their users
accept. The configuration's own files are under the BSD Zero Clause License (`LICENSE`), which every license
above, the GPL included, can be combined with; the files and parts listed under "Code and assets taken into
this repository" keep their own licenses (`THIRD-PARTY-NOTICES`).

Product names, logos and brands (Microsoft, Windows, Visual Studio, NVIDIA, CUDA, Discord, Apple, macOS,
Linux distributions and the rest) belong to their owners; they are named here and drawn in the dashboard
only to say what works with what. This project is not affiliated with, sponsored or endorsed by any of them.

<!-- credits:end -->
