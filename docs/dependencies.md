# Dependencies

Everything this configuration uses: how much it needs each one, and who installs it. `:FeatureStatus` shows what a machine lacks. Install commands per system: [installation](installation.md).

## Levels

| Level | Meaning |
|---|---|
| Required | Without it the configuration does not start, or an error shows at every start. |
| Recommended | It starts; a tool used in most sessions is missing (grep, file search, icons, most Mason packages). |
| Feature | One feature or language only. Everything else works, and `:FeatureStatus` names what is missing. |
| Development | Only for checking and testing this repository. |

## Installers

| Installer | Installs | When |
|---|---|---|
| You | the programs in [system programs](#system-programs) | before the first start |
| lazy.nvim | the [plugins](#plugins), at the commits in `lazy-lock.json` | first start; `:Lazy` (dashboard `l`) |
| Mason | the [Mason packages](#mason-packages): servers, formatters, linters, debug adapters | first start, in the background; `:Mason` |
| nvim-treesitter | the [parsers](#parsers), built here | first start; `:TSUpdate` |

## System programs

### Required

| Program | For |
|---|---|
| Neovim 0.12 or later | everything (0.11.2 starts with a notice; older is refused by LazyVim) |
| `git` | lazy.nvim and the plugins |
| `tree-sitter` CLI and a C compiler (`cc`, `gcc`, `clang` or `cl`) | building the parsers; without them LazyVim reports an error at every start |
| `curl`, `tar` | parser and Mason downloads |
| network access | the first start |

### Recommended

| Program | For |
|---|---|
| `rg` (ripgrep) | grep pickers, ripgrep code search |
| `fd` (or `fdfind`) | file pickers |
| a Nerd Font | icons (Neovide's profile uses CaskaydiaCove Nerd Font Mono) |
| `unzip`, `gzip` | Mason packages from GitHub releases |
| Node.js with `npm` | Mason's npm packages |
| Python 3 with `venv` | Mason's PyPI packages |
| `lazygit` | LazyVim's `<leader>gg` |

### Feature

| Feature | Programs | Systems |
|---|---|---|
| C and C++ navigation | `cscope`, Universal Ctags | all (Windows: cscope registered by path) |
| Code search | `cscope`, `ctags`, GNU Global, `clangd`, `rg` or `fd`, each for its own tool | all |
| CUDA in clangd | the CUDA toolkit (`CUDA_PATH` or `nvcc`) | all |
| Visual Studio projects | Visual Studio or its Build Tools | Windows |
| Debugging C, C++ and assembly | `gdb` 14 or later with Python | Linux; Intel macOS, codesigned |
| | `lldb-dap` (Xcode 16 tools), else Mason's `codelldb` | macOS, Windows |
| Foreign architectures | `qemu-<arch>` and a gdb for the target (`<triple>-gdb` or `gdb-multiarch`) | Linux |
| Linux kernels | [kbuildlab](https://github.com/yugeun-song/kbuildlab); [gdbtools](https://github.com/yugeun-song/gdbtools) optional | Linux |
| Korean input switch and marks | `fcitx5`, `fcitx` or `ibus` | Linux |
| | `macism`, `im-select` or `issw`; `osascript` | macOS |
| | Visual Studio's `cl` or `clang` (builds the helper), else `im-select.exe` | Windows; WSL: `im-select.exe` |
| Window raise for `scripts/open-at.lua` | `hyprctl`, `swaymsg`, `niri`, `kdotool` or `xdotool` | Linux desktops |
| | `osascript` | macOS |
| | the IME helper, else PowerShell | Windows |
| Open Folder | `yazi` | all |
| GUI | Neovide | all |
| Discord Rich Presence | the Discord app | all |
| Man page highlighting | `man` | Linux, macOS |
| Python | `ruff` (server, lint, format) | all |
| Rust | `cargo` and `rustc` (rustup) | all |
| Haskell | `ghc`, `cabal`, `haskell-language-server`, `hlint` (GHCup) | all |
| Common Lisp | `sbcl`; `ocicl` (lint, and installs alive-lsp) | all |
| Racket | `racket` | all |
| Lean | `elan` | all |
| Elixir | `elixir` (Expert, ElixirLS) | all |
| Erlang | `erl` (elp) | all |
| Java and Kotlin | a JDK (jdtls, kotlin-lsp, detekt, ktlint) | all |
| Julia | `julia` (julia-lsp) | all |
| fish | `fish` (`fish_indent`, lint) | all |

### Development

| Program | For |
|---|---|
| `stylua`, `lua-language-server`, `taplo`, `rumdl`, `clang-format` | `scripts/check_repository.lua` (PATH, else Mason's) |
| `podman` or `docker` | `tests/containers/run.sh` |
| `script` (util-linux) | `tests/managed_paths/run.sh` |
| PowerShell and Visual Studio | `tests/windows_ime_helper/run.ps1` |

## Plugins

Installed by lazy.nvim. Loads on: the event, filetype, command or key that loads it (`start`: at startup).

| Plugin | For | Loads on |
|---|---|---|
| lazy.nvim | plugin manager | start |
| LazyVim | the base distribution | start |
| snacks.nvim | pickers, dashboard, notifications, explorer | start |
| markview.nvim | Markdown rendered in place | start |
| neov-ime.nvim | IME preedit | start, Neovide only |
| which-key.nvim | key hints | VeryLazy |
| lualine.nvim | statusline | VeryLazy |
| bufferline.nvim | buffer tabs | VeryLazy |
| noice.nvim, nui.nvim | messages and command line | VeryLazy |
| flash.nvim | jump by label | VeryLazy |
| mini.ai | text objects | VeryLazy |
| mini.pairs | auto pairs | VeryLazy |
| ts-comments.nvim | comment strings | VeryLazy |
| gitsigns.nvim | git signs and hunks | VeryLazy |
| nvim-lspconfig, mason-lspconfig.nvim | language server configurations | VeryLazy |
| mason.nvim | Mason packages | with nvim-lspconfig, `:Mason` |
| nvim-treesitter | parsers and highlighting | first file, else VeryLazy |
| nvim-treesitter-textobjects | tree-sitter motions | VeryLazy |
| nvim-ts-autotag | HTML and JSX tags | first file |
| nvim-lint | linting | first file |
| todo-comments.nvim | TODO highlights | first file |
| persistence.nvim | sessions | first file read |
| blink.cmp, friendly-snippets | completion, snippets | Insert mode, command line |
| conform.nvim | formatting | first save, `:ConformInfo` |
| nvim-hlslens | search count | first search |
| mini.icons | icons | first use |
| mini.files | file explorer | its keys |
| trouble.nvim | diagnostics lists | its keys, `:Trouble` |
| grug-far.nvim | search and replace | its key, `:GrugFar` |
| cscope_maps.nvim, telescope.nvim, plenary.nvim | cscope, the `<leader>i` and code search picker | `<leader>i` keys, `:Cscope`, code search |
| nvim-dap, nvim-dap-view, nvim-dap-disasm | debugger and its panels | debug keys, `:Dbg*` |
| nvim-dap-python | Python tests under the debugger | its keys |
| rustaceanvim | Rust | Rust files |
| haskell-tools.nvim | Haskell | Haskell and Cabal files |
| lean.nvim | Lean | Lean files |
| lazydev.nvim | Neovim's Lua API in lua_ls | Lua files |
| baleia.nvim | ANSI colours in the gdb console | `:BaleiaColorize`, the console |
| tokyonight.nvim, catppuccin, kanagawa.nvim, gruvbox-material | colorschemes besides spaceduck-remix | `:colorscheme` |

## Mason packages

Installed by Mason on every system with a build; with none, a program of the same name on PATH serves. "Needs" is what it needs on PATH to install or run; on Windows a package whose runtime is missing is not installed ([language servers](features/lsp.md#mason-packages)).

| Package | For | Needs |
|---|---|---|
| clangd | C, C++, CUDA, assembly server | |
| clang-format | C and C++ formatting | Python 3 |
| codelldb | LLDB debugging (macOS, Windows, Rust) | |
| lua-language-server | Lua server | |
| stylua | Lua formatting | |
| rust-analyzer | Rust server (through rustaceanvim) | |
| ty | Python server | Python 3 |
| debugpy | Python debugging | Python 3 |
| vtsls | JavaScript and TypeScript server | Node.js |
| oxlint | JavaScript and TypeScript lint | Node.js |
| oxfmt | JavaScript, TypeScript, CSS, HTML and JSON formatting | Node.js |
| js-debug-adapter | JavaScript and TypeScript debugging | Node.js |
| html-lsp | HTML server | Node.js |
| css-lsp | CSS server | Node.js |
| json-lsp | JSON server | Node.js |
| yaml-language-server | YAML server | Node.js |
| yamllint | YAML lint | Python 3 |
| taplo | TOML formatting | |
| rumdl | Markdown lint | |
| bash-language-server | shell server | Node.js |
| shellcheck | shell lint (through bash-language-server) | |
| shfmt | shell formatting | |
| awk-language-server | awk server | Node.js |
| docker-language-server | Dockerfile server | |
| wasm-language-tools | WebAssembly text server | |
| jdtls | Java server | a JDK |
| kotlin-lsp | Kotlin server | a JDK |
| detekt | Kotlin lint | a JDK |
| ktlint | Kotlin lint | a JDK |
| expert | Elixir server | Elixir |
| elixir-ls | Elixir debugging (its debug adapter) | Elixir |
| elp | Erlang server | Erlang |
| julia-lsp | Julia server | Julia |

Not from Mason: `ruff` (PATH), haskell-language-server (GHCup), alive-lsp (ocicl), and the second clangd for assembler (`clangd_asm`, the same `clangd`).

## Parsers

Built by nvim-treesitter with the `tree-sitter` CLI and a C compiler: asm, awk, bash, c, commonlisp, cpp, css, cuda, devicetree, diff, dockerfile, eex, elixir, erlang, git_config, git_rebase, gitattributes, gitcommit, haskell, heex, html, java, javascript, jsdoc, json, julia, kconfig, kotlin, linkerscript, lua, luadoc, luap, make, markdown, markdown_inline, printf, python, query, racket, regex, rust, toml, tsx, typescript, vim, vimdoc, xml, yaml.
