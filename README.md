# nvim-config

A [LazyVim](https://www.lazyvim.org/)-based Neovim configuration tuned for **Linux kernel / C development**, with a GDB-native debugger, a per-path LSP gate, Korean input-method integration, an on-screen keystroke display, a hand-written colorscheme and a Neovide profile.

It is built on Arch Linux with Hyprland, kitty and fcitx5; [Environments](#environments) lists what changes elsewhere and what is not supported, and `:checkhealth config` reports it for the running system.

---

## Highlights

- **LazyVim base** with this repo's `lua/plugins/` on top.
- **C/C++**: indentation from `.editorconfig`/`.clang-format` or the file, no autoformat; clangd, cscope and `tags` tuned for big trees.
- **Low-level highlighting** for `.S`/`.s`, inline `asm("…")`, linker scripts and device trees; man pages with highlighted code.
- **Debugger on GDB's own DAP** for userspace, QEMU user mode and Linux kernels behind a QEMU gdbstub; LLDB on macOS; Python, Rust, JS/TS and Elixir use their own adapters.
- **`lsp_filter`** turns clangd (or any server) off per file or directory.
- **Korean IME integration**, **ChKeys** keystroke display, **`spaceduck-remix`** colorscheme, **Neovide** profile.
- **Open Folder**: pick a folder in yazi from the dashboard and switch the editor to it, its session coming back.
- **Dashboard header**: the running system's logo beside NVIM, in the logo's own colour.

---

## Requirements

| Group | Tool | Why |
|-------|------|-----|
| **Core (required)** | Neovim **0.12+** | nvim-treesitter's `main` branch; LazyVim's own floor is 0.11.2. |
| | `git` | lazy.nvim, plugins, the statusline tag. |
| | `tree-sitter` CLI, a C compiler, `curl`, `tar` | nvim-treesitter (`main`) builds the parsers. |
| | Network access | The first launch installs everything. |
| **Search / UI (recommended)** | `ripgrep` (`rg`), `fd` | Snacks picker and grep. |
| | A **Nerd Font** | Icons and statusline glyphs. |
| **C / kernel workflow** | `clangd` | C/C++ language server (Mason installs one too). |
| | `cscope` | Symbol navigation. Windows has no native build: register one by path (`<leader>uX`), e.g. MSYS2's (`pacman -S cscope`). |
| | `universal-ctags` | The `tags` file behind `<C-]>`. |
| **Debugging (optional)** | `gdb` **14+** with Python | The debug adapter is GDB itself. |
| | `lldb-dap` (Xcode 16 tools) or Mason's `codelldb` | macOS: C and C++, where gdb cannot debug. Windows: beside gdb, for MSVC builds whose PDB gdb cannot read. `vim.g.dbg_lldb` names another and offers the LLDB configurations on any system. |
| | `codelldb`, `js-debug-adapter`, `debugpy`, `elixir-ls` | The other adapters (Mason). |
| | `qemu-system-*` | Bare-metal and QEMU-user targets. |
| | [kbuildlab](https://github.com/yugeun-song/kbuildlab) | Kernel targets: guests, gdb and session come from `kbuildlab attach --json`; without it kernel debugging is off. |
| | [gdbtools](https://github.com/yugeun-song/gdbtools) (optional) | Early-boot kernel symbols, `cfgjson` and `addr2sym`, sourced into each gdb when installed. |
| | `<triple>-gdb` (optional) | For a foreign target, else `gdb-multiarch` or a host `gdb` built for it. One run of each gdb tells whether it starts, its Python works, it is 14 or newer and it knows the target; a broken one is skipped with a notice. `vim.g.dbg_gdb` (a string, or a table by arch) overrides; kernel sessions run kbuildlab's gdb. |
| | `qemu-<arch>` usermode (optional) | Foreign-architecture userspace (`qemu-user`). |
| | `/usr/<triple>` or `/usr/<triple>/sys-root` (optional) | Sysroot for dynamic cross binaries, when present. |
| **Common Lisp (optional)** | `sbcl`, `ocicl` | alive-lsp, REPL, lint. |
| **Racket (optional)** | `racket` | REPL and `K` docs; no `raco` packages. |
| **Haskell (optional)** | `ghc`, `cabal`, `haskell-language-server`, `hlint` from [GHCup](https://www.haskell.org/ghcup/) | `~/.ghcup/bin` joins the end of `PATH`. |
| **Lean (optional)** | `elan` | The project's Lean toolchain (not Mason). |
| **Python (optional)** | `ruff` | Lint and format beside `ty` (Mason). |
| **IME reset (optional)** | `fcitx5`, `fcitx` or `ibus` (Linux); `macism`, `im-select` or `issw` (macOS); `winctl`, built from `scripts/winctl.c` by Visual Studio's `cl` (or clang targeting MSVC), else `im-select.exe` (Windows); `im-select.exe` (WSL) | English on leaving Insert; the `한`/`EN` indicator reads fcitx5 on Linux, the same tool on macOS and `winctl` on Windows. |
| **Open Folder (optional)** | [yazi](https://yazi-rs.github.io/) | The folder picker; without it the dashboard entry and key are not created. |
| **Caps Lock indicator (optional)** | Linux sysfs LED node; `osascript` (macOS); `winctl` (Windows) | `/sys/class/leds/input*::capslock/brightness`. |
| **GUI (optional)** | [Neovide](https://neovide.dev/), `CaskaydiaCove Nerd Font Mono` | The GUI profile. |
| | `wl-clipboard` or `xclip` | `+` register for the GUI paste key. |
| **Discord presence (optional)** | Discord desktop client (or Vesktop) | Linux, macOS and Windows. |
| **Editing the config (optional)** | `lua-language-server`, `stylua` | From Mason. |
| **Terminal (optional)** | kitty / WezTerm / foot / ghostty / rio | kitty keyboard protocol for ChKeys. |

> For the kernel workflow, generate the index files from the source tree: `make C=2 compile_commands.json` (or `scripts/clang-tools/gen_compile_commands.py`), `make cscope`, `make tags`.

---

## Environments

| Environment | What changes | Status |
|---|---|---|
| Arch Linux on x86_64, Hyprland, kitty or Neovide, fcitx5 | The baseline it is built and tested on. | Full |
| Debian, Ubuntu, Fedora, openSUSE | Package names differ (`fdfind`, Fedora's `/usr/<triple>/sys-root`); Debian, Ubuntu and Alpine need `gdb-multiarch` for foreign targets; Debian 12 and Ubuntu 22.04 ship gdb 13 and 12, which have no DAP; openSUSE Leap's gdb has no riscv64; Debian's Mason Python packages need `python3-venv`. | Full |
| NixOS | Mason's downloaded binaries need `nix-ld`; a QEMU-user launch needs its `sysroot` set by hand. | Full with `nix-ld` |
| musl (Alpine, Void musl) | Mason has no musl `clangd` or `codelldb`; the distribution's are used. | Full with system tools |
| Linux on aarch64 | Mason has no Linux arm64 `clangd`; gdb is chosen for the host architecture. | Full |
| Sway, niri, KDE Plasma 6, X11 | `scripts/open-at.lua` raises the window through `swaymsg`, `niri`, `kdotool` or `xdotool`. | Full |
| GNOME on Wayland | No program may raise a window, so `scripts/open-at.lua` opens the file without bringing the window forward. | Raise unsupported |
| Other terminals, tmux, Zellij | The background follow needs OSC 11 and OSC 111 and is skipped inside tmux, screen, Zellij and nested Neovim; foot gets its IME mode sequence. | Full |
| ibus, fcitx4 | The IME still returns to English; the `한`/`EN` indicator reads fcitx5. `langmap` assumes Dubeolsik. | Indicator unsupported |
| No `$XDG_RUNTIME_DIR` | The focus records move to `stdpath("state")`. | Full |
| macOS | IME switch and `한`/`EN` through `macism`, `im-select` or `issw`; Caps Lock and window raise through `osascript`; Discord through its socket. C and C++ debug through LLDB with the Registers, Memory and Disassembly panels, since gdb cannot debug on Apple silicon (an Intel gdb must be codesigned). QEMU user mode and kernels are Linux-only. | Partly |
| Windows | Paths under `%LOCALAPPDATA%`; Mason's `.cmd` shims and GHCup's `C:\ghcup\bin` are handled. `winctl` (built at the first start) switches the IME, feeds the `한`/`EN` and `CAPS` indicators and raises windows; Visual Studio's MSVC environment is set as in a Developer Prompt; clangd asks MinGW's gcc for its includes; C and C++ also debug through LLDB; programs off PATH, such as MSYS2's `cscope`, are registered by path. Faster than stock: answered program lookups, matchit and netrw loaded early, background plugin checks two at a time ([Windows](#windows-luawinctllua-luaconfigwhichlua)). No `:Man`, no Mason `elp`, gdb from MSYS2 or WinLibs (found under `C:\msys64` when not on PATH); QEMU user mode and kernels are absent. | Partly |
| WSL | As Linux; the IME switches through `im-select.exe`. No window raise, and the Windows Discord client is out of reach. | Partly |
| SSH | The background follow reaches the local terminal and the clipboard goes through OSC 52; the IME switch and the window raise would act on the remote host. | Partly |
| Neovim 0.11 or older | nvim-treesitter's `main` branch needs 0.12. | Unsupported |

---

## Installation

Neovim reads `$XDG_CONFIG_HOME/nvim` (default `~/.config/nvim`). Move an existing config aside, clone and link (or clone straight into `~/.config/nvim`):

```zsh
mv ~/.config/nvim ~/.config/nvim.bak 2>/dev/null
git clone https://github.com/yugeun-song/nvim-config.git ~/workspace/nvim-config
ln -s ~/workspace/nvim-config ~/.config/nvim
nvim
```

On Windows the config directory is `%LOCALAPPDATA%\nvim` and the data directory `%LOCALAPPDATA%\nvim-data`:

```powershell
git clone https://github.com/yugeun-song/nvim-config.git $env:LOCALAPPDATA\nvim
nvim
```

To try it beside your own config, give it a separate `NVIM_APPNAME` (Neovim then uses `~/.config/test-nvim`, `~/.local/share/test-nvim`, …):

```zsh
git clone https://github.com/yugeun-song/nvim-config.git ~/.config/test-nvim
NVIM_APPNAME=test-nvim nvim
```

The first start installs lazy.nvim, the plugins, the parsers and the Mason packages from `lua/plugins/external_programs/mason_packages.lua` (into the data directory's `mason/`, `~/.local/share/nvim/mason/` on Linux and macOS). Check with `:Lazy` and `:LazyHealth`, then restart once. `:checkhealth config` lists what each feature needs here: ready, missing, or not supported on this system. Update plugins with `:Lazy update` (commits are recorded in `lazy-lock.json`) and the config with `git pull`.

Neovide reads its own settings from `~/.config/neovide`; link the ones here:

```zsh
ln -s ~/.config/nvim/neovide ~/.config/neovide
```

On Windows that is `%APPDATA%\neovide`; a junction needs no administrator:

```powershell
New-Item -ItemType Junction -Path $env:APPDATA\neovide -Target $env:LOCALAPPDATA\nvim\neovide
```

Icons need a Nerd Font in the terminal too (`CaskaydiaCove Nerd Font Mono`, as in Neovide). On Windows, `nvim.exe` started outside a terminal opens in the console host with its own font; make Windows Terminal the default terminal application (Settings → System → For developers) to get its font there. kitty's cells are 90 % of the advance at 11 pt; Windows Terminal's `"font": { "size": 11, "cellWidth": "0.9ch" }` matches them. Windows Terminal also binds Ctrl+C and Ctrl+V to copy and paste; bind those actions to Ctrl+Shift+C and Ctrl+Shift+V, as kitty does, so `<C-v>` (Visual block) and `<C-c>` reach Neovim.

---

## Repository structure

```text
nvim-config/
├── init.lua                  # Windows lookups and MSVC, tool paths, open_folder, remote_open, terminal_background, config.lazy
├── lazy-lock.json            # plugin lockfile
├── lazyvim.json              # LazyVim extras (mini.files)
├── .editorconfig             # indentation and line ends for every editor
├── .gitattributes            # LF in every checkout, Windows' core.autocrlf included
├── .luarc.json               # lua_ls runtime and globals (lazydev adds the libraries)
├── .rumdl.toml               # Markdown lint rules
├── stylua.toml               # StyLua style
├── after/
│   ├── ftplugin/
│   │   ├── lisp.lua          # Lisp buffer settings, REPL keys
│   │   ├── racket.lua        # Racket buffer settings, REPL keys
│   │   └── man.lua           # man windows, man_code passes
│   └── queries/              # Tree-sitter injections:
│       └── asm/injections.scm #   C in .S/.s directives
├── colors/spaceduck-remix.lua # the colorscheme
├── neovide/config.toml       # Neovide's own settings (fork), linked to ~/.config/neovide
├── queries/asm/highlights.scm # tree-sitter-asm colours only comments and strings
├── tests/stored_data_paths/              # stdpath() and the managed paths under every layout: run.sh, run.ps1, docker.sh
├── tests/winctl/             # winctl: run.ps1 (all), unit.c, fuzz.c, test.lua (Neovim-driven), bridge.lua (Lua side)
├── scripts/
│   ├── alive-lsp-stdio.lisp  # alive-lsp launcher
│   ├── open-at.lua           # FILE LINE into the focused Neovim, for heaptrack and other tools
│   ├── reset.lua             # list what Neovim keeps where; typing reset goes back to a fresh clone
│   ├── .clang-format         # winctl.c's style: Microsoft-based, braces on every body
│   └── winctl.c              # Windows helper: IME, Caps Lock, window raise, tool shims
└── lua/
    ├── chkeys.lua            # keystroke display
    ├── winctl.lua            # builds and finds scripts/winctl.c (Windows)
    ├── msvc_env.lua          # Visual Studio's MSVC environment, captured once (Windows)
    ├── msvc_compiledb.lua    # compile_commands.json from MSBuild, as IntelliSense reads it (Windows)
    ├── cuda_clangd.lua       # clangd for .cu files: nvcc commands as clang's, nvcc-only spellings
    ├── tool_paths.lua        # programs registered by path, shims at the end of PATH
    ├── tool_discovery.lua    # where Windows records programs: registry, installs, vswhere
    ├── managed_paths.lua     # where Neovim, the plugins and Neovide keep what they write; the reset
    ├── dashboard_header.lua  # dashboard header: system logo and NVIM
    ├── lisp_repl.lua         # sbcl and racket REPLs
    ├── open_folder.lua       # Open Folder, folder arguments, recent folders
    ├── remote_open.lua       # focused instance and window raise for scripts/open-at.lua
    ├── terminal_background.lua # the terminal's background follows Normal (OSC 11)
    ├── indent_motion.lua     # h/l/arrows step by shiftwidth through leading spaces
    ├── asm_highlight.lua     # assembly colours in asm buffers and asm("…") templates
    ├── asm_navigation.lua    # gd and K in asm buffers: clangd, tags, cscope, then the built-in
    ├── macro_highlight.lua   # C/C++ code where tree-sitter swapped strings and code
    ├── dbg/                  # GDB debugger support:
    │   ├── discover.lua      #   ELF reading, gdb choice, kbuildlab and gdbtools lookup
    │   ├── breakpoints.lua   #   function/address breakpoints, run-to
    │   ├── allstop.lua       #   changes on a running remote target
    │   ├── adapter.lua       #   gdb process lifecycle
    │   ├── cfg.lua, cfgbox.lua #   control-flow graph
    │   ├── console.lua       #   gdb console
    │   ├── disasm.lua        #   pc mark, branch connector
    │   ├── inline.lua        #   inline values
    │   ├── notify.lua        #   messages, :DbgLog
    │   ├── watch.lua         #   Locals+Globals panel
    │   ├── watchdog.lua      #   lost gdbstub warning
    │   ├── context.lua       #   session profile
    │   ├── qemuser.lua       #   QEMU user-mode gdbstub
    │   ├── kernel.lua        #   kernel picker and attach
    │   ├── caps.lua          #   target capabilities
    │   ├── gdbq.lua          #   gdb commands through DAP
    │   ├── qemumon.lua       #   QEMU monitor, read guard
    │   ├── memory.lua        #   hex view
    │   ├── registers.lua     #   register panel
    │   ├── mappings.lua      #   memory map panel
    │   ├── session.lua       #   stop, continue, step, target panel
    │   ├── layout.lua        #   window layouts
    │   ├── panel.lua         #   buffer/window plumbing
    │   └── ui.lua            #   highlights, banners
    ├── config/
    │   ├── lazy.lua          # bootstrap
    │   ├── options.lua       # options, filetypes
    │   ├── keymaps.lua       # ChKeys, indent_motion
    │   ├── ime.lua           # IME tool and statusline sources
    │   ├── which.lua         # executable()/exepath() answers kept per PATH (Windows)
    │   ├── runtimes.lua      # what each Mason package needs to run
    │   ├── mason_windows.lua # Mason packages held back on Windows
    │   ├── health.lua        # :checkhealth config
    │   └── autocmds.lua      # C indent, #include gf, cscope, tagfunc, prose
    ├── man_code/             # man page highlighting (code, structure)
    ├── lsp_filter/           # per-path LSP gating (init, rules, util)
    ├── ifdef_all/            # all #if branches toggle (init, scan)
    └── plugins/              # specs, one file per feature:
        ├── dap.lua, dap_languages.lua # nvim-dap, GDB adapters, keys; other debuggers
        ├── clangd.lua, cscope.lua, asm.lua, ifdef_all.lua # C workflow, all #if branches, low-level highlighting
        ├── treesitter.lua, formatting.lua, linting.lua # parsers, oxfmt/taplo, ktlint/detekt/yamllint
        ├── python.lua, elixir.lua, haskell.lua, lisp.lua, lean.lua # per-language setup
        ├── im_control.lua, imstate.lua # langmap, IME reset, statusline state
        ├── lualine.lua, git_tag.lua, hlslens.lua, noice.lua # statusline, tag, search index
        ├── snacks.lua, mini-files.lua, markview.lua, diagnostics.lua, trouble.lua # pickers, explorer, markdown, floats, Trouble splits
        ├── open_folder.lua   # Open Folder entry and key, Projects with recent folders
        ├── colorscheme.lua, neovide.lua, neovide-ime.lua # spaceduck-remix, GUI
        ├── ansi_color.lua, discord_rpc.lua, fs_refresh.lua # baleia, presence, reload
        ├── tool_paths.lua    # <leader>uX and :ToolPath
        ├── managed_paths.lua # <leader>uM, :ManagedPaths, :ManagedPathsReset
        ├── msvc.lua          # :MsvcCompileDb (Windows)
        └── lsp_filter.lua, mason.lua, mason_windows.lua # filter keys, Mason packages, Windows' hold-backs
```

## Features in detail

### Base (`init.lua`, `lua/config/lazy.lua`, `lua/config/options.lua`)

lazy.nvim (stable) is cloned on first run and imports LazyVim plus `lua/plugins/`. Plugins load at startup and track their latest commit, with silent update checks. Options: absolute line numbers, `tags = "./tags;,tags;"`, a bar cursor in Insert mode, no modelines, no swap files (so no swap recovery), `h`/`l`/arrows wrap across lines, node/perl/ruby providers off. In leading spaces `h`/`l`/arrows (and Insert-mode arrows) step by `shiftwidth`, as over a tab (`lua/features/editing/indent_stop_motion.lua`); `x`/`dl` still take one space.

### Prose buffers (`lua/config/autocmds.lua`)

`text`, `plaintex`, `typst`, `gitcommit` and `markdown` buffers wrap but keep spell off; `<leader>us` toggles it, and `spelllang = en,cjk` leaves Hangul, Han and kana alone. LSP clients are detached from `claude-prompt-*.md`, the file Claude Code opens on `Ctrl+G`.

### Linux kernel C workflow (`lua/config/autocmds.lua`, `lua/plugins/languages/c_and_cpp_clangd.lua`, `lua/plugins/languages/cscope.lua`)

- **Indentation.** A `.clang-format` found upward sets it (`IndentWidth`, `UseTab`, `TabWidth` or the `BasedOnStyle` default); a project `.editorconfig` wins. With neither, a buffer whose first 2000 lines start more often with a tab than with two spaces gets 8-column tabs, else 4 spaces. Existing whitespace is never rewritten; `list` is on and autoformat off.
- **clangd**: `--background-index --clang-tidy --completion-style=detailed --header-insertion=never --pch-storage=disk --background-index-priority=background --limit-results=200 --limit-references=2000 --log=error -j=<all CPUs>`; preambles go to a private per-instance directory under `stdpath("cache")`, removed when that Neovim exits.
- **cscope**: `cscope_maps.nvim` with Telescope under `<leader>i`; reading a `*.c`/`*.h`/`*.S` file adds the nearest `cscope.out` above it, once per session. cscope reads assembler as C, so `find g` drops an assembler hit only when its line proves a use (the word heads the statement, is a `\parameter` or a directive's name, or sits in an expression) and its file spells nothing else that could define the word. A bare operand, a `.globl` and a macro's argument stay, and every hit stays when all would go. Losing a definition is worse than showing a use.
- **`<C-]>`**: the LSP `tagfunc` is cleared in C/C++ and assembler buffers, so it jumps through `tags` (`make tags`).
- **`gf`** on an `#include` line follows the project's own tools: with a project `compile_commands.json` or `compile_flags.txt`, clangd's header when it is in the project or a system one; else a matching `tags` file entry, `cscope.out` file or `cscope.files` line (a picker when several match); else the built-in `gf`.
- **`gd` in assembler** (`lua/features/languages/assembly/definition_navigation.lua`): clangd's answer for a word's `#define` or an `#include` line, else the definitions in the file itself, from `tags` or spelled on a line (label, `=`, `.set`, `.equ`, `.macro`, `.req`), which answer alone unless `#if` or `.if` encloses them. Otherwise every place that may define the word is listed, nearest first: tagged or spelled definitions in the files it includes, macro calls in this file (`SYM_FUNC_ALIAS(name, ...)`), a macro of this file taking the word, all other tags, what cscope spells, and macro calls at file scope that `cscope find s` sees (`DEFINE_PER_CPU(type, name)`). Left out is only what assembler cannot name: a member, a C type, a C static of another file, a `.c` file's `#define`; in a comment, those count too. With none of that, prototypes and other tags that define nothing, then a macro's arguments elsewhere, then the built-in `gd`. One hit jumps, several open the `<leader>i` Telescope picker. A second clangd (`clangd_asm`, no background index or tidy) attaches to `asm` buffers and leaves one the project's clangd configuration cannot read as C (no such configuration, or a plain `.s`). That reading is true only for the preprocessor, so `gd` and `K` take clangd's answer only for a word's `#define` or on an `#include` line, and the client offers nothing else: no completion, tokens, formatting or diagnostics. `gr`, `gy` and the like have nothing to answer with; `<leader>is` lists a symbol's uses. A `\name` operand is a `.macro` parameter and goes straight to the built-in `gd`.
- **All `#if` branches**: `<leader>uB` (off by default, saved, followed by every running nvim) colours every preprocessor branch and answers hover, definition and completion in the inactive ones through an extra clangd per inactive branch.

### CUDA (`lua/features/languages/cuda/clangd_for_cuda.lua`)

clangd parses `.cu` and `.cuh` files in clang's CUDA mode on every system; three things make nvcc's code read as nvcc reads it. Nothing here runs for C or C++ files.

- **nvcc compile commands.** A database written for nvcc (CMake's, Bear's) holds options clang does not take, and no toolkit, so `__global__`, `threadIdx`, `dim3` and even a correct `<<<` came back as errors. An open CUDA file whose command is nvcc's gets the clang command that compiles it the same way, through clangd's `compilationDatabaseChanges`: include directories (also from `--options-file` and `-isystem=`), definitions (also `-Xcompiler` ones, `-D` or cl's `/D`), the standard, the first GPU of `-arch`/`-gencode`, and the toolkit that nvcc belongs to. The database is not touched; a command that is already clang's is left alone.
- **nvcc-only spellings.** nvcc accepts a launch with spaces between its angle brackets (`k << <grid, block >> > (args)`, as Visual Studio's formatter writes it); clang lexes only `<<<` and `>>>`. Its errors there, and the comma warnings its arguments then get, are dropped from CUDA files, and only on such a launch. So is "not used directly" for `cuda_runtime.h`, `cuda_runtime_api.h`, `cuda.h` and `device_launch_parameters.h`, which every CUDA compilation includes by itself.
- **No compile command.** clang looks for a toolkit only in a few places (`/usr/local/cuda`, beside `ptxas` on PATH; on Windows only where CUDA 7 and 8 went), so clangd's fallback flags name the one in `CUDA_PATH` (NVIDIA's installer on Windows, Arch's `cuda` package), else the one `nvcc` on PATH belongs to.

Everything else clang reports stays, warnings included: a `goto` past an initialization, for one, is what nvcc (#546-D) and cl (C4533) warn about too.

### Low-level highlighting (`lua/plugins/languages/assembly.lua`, `after/queries/`)

In `.S`/`.s`, a line that starts with a preprocessor directive is parsed as C; a `#` comment after an instruction stays a comment. `lua/features/languages/assembly/syntax_highlighting.lua` colours assembly in `asm` buffers and C/C++ `asm("…")` templates, since tree-sitter-asm misparses labels, dotted mnemonics and GCC operands (it keeps only comments and strings); a token it does not know stays plain. `lua/features/languages/c_and_cpp/macro_body_highlighting.lua` recolours C/C++ code whose strings tree-sitter misreads: after `#x`, `a##b` or a macro used as an `asm` template, the parser can drop a quote and swap strings and code. A `#define` body is re-parsed with those constructs masked (lexer colours where that still fails), a function line gets lexer colours, and `asm` templates keep their assembly colours. `.S`/`.s`/`.sx` are `asm`, `*.lds`/`*.ld`/`*.lds.S` `linkerscript`, `*.dts`/`*.dtsi` `devicetree`. This is injection, not preprocessing: `#if 0` bodies stay highlighted.

### Man pages (`after/ftplugin/man.lua`, `lua/features/appearance/man_page_highlighting/`)

`:Man` buffers keep the global `number`, `relativenumber` and `signcolumn`. Code blocks are parsed with the C grammar (sections 0, 2 to 5, 7, 9 and suffixes such as `3p`; another suffix names its grammar), skipping prose, within 100 ms per page. Headings, options and `name(section)` references are re-marked above roff's bold, so the `man*` highlight groups show.

### Debugging (`lua/plugins/debugging/debug_adapter.lua`, `lua/features/debugging/low_level/`)

C, C++ and assembly are debugged by GDB itself (`gdb -i dap`), so `~/.gdbinit`, pwndbg and other GDB Python tooling load as usual. On macOS the *(lldb)* configurations launch and attach through `lldb-dap` or `codelldb` instead. Other languages use their own adapters (`lua/plugins/debugging/other_language_debuggers.lua`):

| Language | Debug support | What it brings |
|---|---|---|
| C / C++ / asm | `gdb -i dap` | The panels below, QEMU user mode, gdbtools |
| Linux Kernel | `gdb -i dap` (`gdb_kernel`) | The same, plus kernel attach |
| C / C++ on macOS | `lldb-dap` or `codelldb` | Launch, launch to `main`, attach; Registers, Memory, Disassembly, function and address breakpoints |
| Python | [`nvim-dap-python`](https://github.com/mfussenegger/nvim-dap-python) on `debugpy` | Its configurations, the test under the cursor |
| Rust | [`rustaceanvim`](https://github.com/mrcjkb/rustaceanvim) on `codelldb` | `:RustLsp debuggables`, LLDB's Rust formatters |
| JavaScript / TypeScript | `js-debug-adapter` | `pwa-node`/`-chrome`/`-msedge`; `.ts` on Node's type stripping, or `tsx`/`ts-node` if installed |
| Elixir | [ElixirLS](https://github.com/elixir-lsp/elixir-ls)'s adapter (`mix_task`) | `mix test` and `mix run` |

`.vscode/launch.json` is read for every language; Julia and Java have no debugger. The rest applies to `gdb` and `gdb_kernel` sessions; an `lldb` session gets the Registers, Memory and Disassembly panels and the function and address breakpoints, and the panels that run gdb commands stay gdb-only; others get plain `nvim-dap-view`.

- **Programs.** Launch, launch to `main`, attach by PID, *Run on QEMU user* (Linux; `qemu-<arch> -g` on a private Unix socket with the toolchain's sysroot, stopped at `_start`; x86_64, aarch64, riscv64, arm) and *Attach to a QEMU user gdbstub*. The executable and shell-quoted arguments are remembered: `<leader>dc` with no session replays the last run, `<leader>dn` asks again. A cross target gets `vim.g.dbg_gdb`, else the first `<triple>-gdb`, `gdb-multiarch` or host `gdb` that runs DAP and knows the architecture; with none the session does not start and says why, naming the package to install. gdbtools is sourced from `$GDBTOOLS_PATH` or the checkout its `setup.sh` recorded.
- **Kernel targets.** `<leader>dq` lists the guests from `kbuildlab attach --list --json` (tree, boot mode, KASLR, whether a debugger holds the stub; a busy stub is refused); a guest kbuildlab did not start is attached by picking its registered tree and port. It then asks: attach where the kernel is, or early boot (`:DbgKernelEarly` skips the question), which runs `kearly on` and `kearly bootbreak arm` and continues to the first `head.S` instruction; `kearly kaslr auto` is left to you.
- **Kernel adapter.** Each start asks `kbuildlab attach TREE --port N --json` for the gdb, its `-iex` lines, gdbtools, the vmlinux, the target and QEMU's pid, so a replayed configuration follows a guest restarted in another boot mode. A vanished QEMU or a lost connection is announced, and the panels stay.
- **All-stop remotes.** A remote target takes no command while it runs: a breakpoint change is held, the target interrupted unseen by nvim-dap, the change sent, the target resumed. If it does not stop within 2 s, the change waits for its next stop (said once).
- **Stopping.** `<leader>dt` detaches an attached target (interrupting it first) and terminates a launched one; `<leader>dT` kills, ending a QEMU guest. Quitting Neovim ends every session the same way and kills any leftover `gdb -i dap`.
- **Breakpoints.** Line breakpoints are allowed without DWARF (a library may carry it); refused ones are reported with gdb's message, unbound ones with the likely reason. `<leader>dF` breaks on a function or `0x` address with no line table. Pending breakpoints keep one sign each, and a breakpoint gdb makes itself (the stop-at-main `tbreak`) never replaces yours on the same line.
- **Run to cursor and stepping.** `<leader>dC` runs to the source line or disassembly address under the cursor through gdb's own one-shot breakpoint, so your breakpoints stay set (nvim-dap's run-to-cursor would clear them all). The frame selection returns to frame 0 after nvim-dap picks a caller with source, so every view agrees; without source, steps go by instruction and the disassembly is shown.
- **Panels** (`nvim-dap-view` tabs; the label's letter switches): Scopes, Locals+Globals (frame and file variables, `static` included, optimised-out ones tagged `opt`), Watches, Registers (`<symbol+offset>`, change marks), Memory (hex view of an expression, a physical address or a file, 8 KiB per window), Mappings (pwndbg's `vmmap`), Control flow (gdbtools' `cfgjson`; `:DbgControlFlow` puts it in the source window), Disassembly (pc highlight, connector to a taken branch), Call stack, Breakpoints, Target, gdb console and Output. A stop refreshes only the panels on screen; a hidden one catches up when shown, and Target asks fixed facts (architecture, endianness, checksec) once per session (`r` re-asks). Values also show at the end of lines using them (`:DbgInline off`).
- **gdb console**: GDB's own interpreter with ANSI colours. `c`, `n`, `s`, `ni`, `si`, `finish`, `q`, `kill` go through nvim-dap so the panels stay in step; `<CR>` runs the line under the cursor, `<C-x><C-o>` completes.
- **`:DbgState`** says what the session supports (line, function and instruction breakpoints, source stepping, disassembly, QEMU monitor) and why not.
- **Guarded reads.** A read outside guest RAM can take QEMU down, so under `:DbgSafeMem auto` a kernel session checks the address with `monitor gva2gpa`/`gpa2hva` on every core, reads physical-only RAM through `monitor xp`, and refuses a device region or hole. `o` reads anyway; `on`/`off` guard every session or none.
- **Windows.** Source opens in a file window, never a panel; ending a session closes nothing. `<leader>du` toggles the panel, `:DbgClose` restores the pre-session layout. `:DbgLog` shows the last 400 messages and the tail of nvim-dap's log.
- **Layout** depends on `columns` and `lines` only: compact keeps every panel in the bottom bar, wide adds a right-hand column with one panel, Registers first (`]p`/`[p` switch). `:DbgLayout auto|wide|compact` overrides; `:DbgLayoutReset` rebuilds the windows.

  | Terminal | Mode | Side column |
  |---|---|---|
  | 120x32 | compact | — |
  | 140x36 | wide | 53 |
  | 200x50 | wide | 76 |
  | 320x90 | wide | 110 |

### `lsp_filter` — per-path LSP gating (`lua/features/language_servers/attach_rules/`, `lua/plugins/language_servers/attach_rules.lua`)

Turns servers off for generated or vendored subtrees. A rule matches a path prefix (`within`) or segment (`contains`), targets `clangd` unless `<leader>cFa` picks all servers or a list, and detaches the client (`disable`) or hides its diagnostics (`diagnostics_off`). Rules live in `stdpath("data")/lsp_filter/rules.json`, outside every repository, and reload on save. Marker files (`.nvim-lsp-filter.json`) need `setup({ markers_enabled = true })`.

| Want to… | Do this |
|----------|---------|
| Turn clangd off for a directory | Open a file in it, `<leader>cFd`, pick the directory |
| Toggle the whole filter off for now | `<leader>cFt` (session only) |
| Remove a rule permanently | `<leader>cFe` → delete its object from `rules` → `:w` |

### Korean input-method integration (`lua/plugins/input_method/korean_input.lua`, `lua/plugins/input_method/state_indicator.lua`)

`langmap` maps Dubeolsik jamo to their QWERTY keys for Normal mode. On `InsertLeave` and `FocusGained` the IME is set to English, never to Korean, by the first tool found: fcitx5 or fcitx4 (`-remote -c`) or ibus (`ibus engine`, `vim.g.ibus_english_engine`, default `xkb:us::eng`) on Linux, `macism`, `im-select` or `issw` on macOS, `winctl ime-en` (else `im-select.exe`) on Windows, `im-select.exe` on WSL. In foot, its IME mode sequence keeps the IME on only in Insert mode. The statusline shows `󰬈 CAPS` (LED read every 200 ms) and `한`, or `EN`/`en` (`fcitx5-remote -n` on mode, focus and idle events, plus every second); on macOS the input source comes from `macism`, `im-select` or `issw` and Caps Lock from one `osascript` process; on Windows one `winctl watch` process prints both whenever either changes; all of them pause while Neovim is unfocused; `vim.g.caps_state` and `vim.g.im_state` hold the same.

### Windows (`lua/features/windows_platform/winctl.lua`, `lua/features/windows_platform/executable_lookup_cache.lua`)

Everything here sits behind `has("win32")`; Linux and macOS run the same code as before.

- **`winctl`** is `scripts/winctl.c`, kept in this repository and built at the first start (and after the source changes) in the background into `stdpath("data")/winctl`; nothing is downloaded. It targets x86_64 Windows only and builds with Visual Studio's `cl` (on PATH through the MSVC environment below) or clang targeting MSVC; the preprocessor stops any other target or compiler (Linux, macOS, MinGW, 32-bit, ARM64). The build treats warnings as errors, the linker's too, links the C runtime in (the program loads only `kernel32`, `user32` and `imm32`), and must then answer `winctl version` exactly: a library that cannot be found, a corrupt or foreign one, an import that fails to load all discard the build, the next compiler is tried, and the reason is shown in Neovim and kept in `winctl-*.log`. `winctl ime-en` clears the IME's native (Hangul) mode of the foreground window and keeps its keyboard layout, the counterpart of `fcitx5-remote -c`; `winctl watch PID` polls Caps Lock and that mode every 100 ms (polled, not hooked: a keyboard hook would see every key), prints them only on a change, and takes `e` (English), `p` and `r` (pause, resume) on its stdin, so leaving Insert mode and focus changes start no process; `winctl raise PID` walks the process lineage once and brings its window forward. It runs only as Neovim's child (its parent must be `nvim.exe`, checked against reused process ids) and ends with Neovim: the watcher waits on Neovim's process and its stdin. Every input is checked by the function that uses it, every failure ends the command with its reason (exit 2 usage, 3 an unknown command on stdin, 4 not started by Neovim, 127 a shim that may not run), and Neovim shows each failure once and lists them in `:checkhealth config`. What it holds of the input state (Caps Lock, the IME's mode, stdin commands) is wiped once used, and every function releases what it acquired on every path through one exit. Style: `scripts/.clang-format` (Microsoft-based). Tests: `tests/winctl/run.ps1` builds and runs them all: format, `cl /W4 /WX /sdl /analyze`, clang `-Werror` and its analyzer, the preprocessor guards, C unit tests and Neovim-driven tests under AddressSanitizer (refused paths, malformed `.shim` files, a shim killed with its program), the Lua side's own tests (`tests/winctl/bridge.lua`, any system), and a libFuzzer target over the parsers.
- **Program lookups.** Windows' `executable()` and `exepath()` try every PATHEXT extension in every PATH directory, about 10 ms a name with forty directories. Lua callers, `vim.system()` and the plugins included, get the answer from `stdpath("cache")/which.json`, kept per PATH with each directory's mtime (checked again every two seconds), so a program installed meanwhile is seen. A directory that changed is listed once and only the answers it can affect are dropped (a miss it now has a candidate for, a hit it held or now shadows): IncrediBuild's agent, for one, writes into its directory on PATH every few seconds, which used to throw every answer away at each start. A start asks for 4 names (33 ms), 9 with a C file (55 ms); answered, well under 1 ms.
- **matchit and netrw** load before lazy.nvim fills the runtimepath: `:packadd` resolves each entry, 20 ms more apiece on a full one.
- **lazy.nvim's update check** starts git once per plugin (60 processes) and Windows holds the editor about 5 ms on each, which made a terminal such as yazi's stutter in the first seconds. It, and the hourly check, now wait until no key has come for 5 s outside a terminal, or until Neovim loses focus.
- **clangd** gets `--query-driver` for the directories of the compilers on PATH, so a compile database written for MinGW's gcc gets gcc's target and system includes instead of MSVC's; nothing a repository names is run.
- **C and C++ debug through LLDB** (Mason's `codelldb`) beside gdb, for MSVC builds whose PDB gdb cannot read; MinGW builds use gdb as on Linux.
- **MSVC environment** (`lua/features/languages/c_and_cpp/msvc_toolchain/developer_environment.lua`), the counterpart of a Linux system's compiler, libc and kernel headers: vswhere finds the newest Visual Studio with the MSVC tools, its `VsDevCmd` runs once in the background (2 s) and what it changes is kept in `stdpath("state")/msvc_env.json`. Each start sets those variables (`INCLUDE`, `LIB`, `LIBPATH`, the VCTools and Windows SDK ones; none already set is replaced) and appends its directories to PATH, in about 1 ms: clangd reads `INCLUDE` for MSVC's and the SDK's headers, and `:terminal` and `:make` get `cl`, `link`, `nmake` and `msbuild`. A MinGW compile database keeps gcc's target and includes. A start from a Developer Prompt changes nothing; a Visual Studio update is captured again; `<leader>uX` turns it off and on.
- **Visual Studio projects get a compile database the way a kernel tree does** (`lua/features/languages/c_and_cpp/msvc_toolchain/compile_database.lua`), with what IntelliSense reads: MSBuild's design-time target `GetClCommandLines` returns the cl options of every source file (include directories, definitions down to one file's, the language standard). All projects of the nearest `.sln`, `.slnx` or `.vcxproj` go through one MSBuild run, a traversal project with `BuildInParallel` under `-m`, so MSBuild spreads them over the cores (two projects: 0.6 s). `compile_commands.json` goes beside that file; clangd restarts on it and indexes in the background on every core. CUDA projects get their `.cu` files from the same run: `GetClCommandLines` covers `ClCompile` only, so a small target imported through Microsoft.Cpp's `ForceImportAfterCppTargets` hook asks NVIDIA's build customization (`InitializeCudaProjectProperties`) for what it resolved, and each file gets clang's CUDA mode with the project's toolkit (`CudaToolkitDir`), the first GPU of its `CodeGeneration`, and the defines and include directories it inherits from the host compiler; nothing is compiled. Other CUDA files: see CUDA below. Opening a C, C++ or CUDA file rebuilds it, in the background, when it is missing or one of its inputs changed (the solution, each `.vcxproj`, the `.props` and `.targets` they import, `Directory.Build.*`, each compared with the mtime recorded when it was read); when current, that is a few stats. Writing one of those files in Neovim checks again. A `compile_commands.json` this did not write (CMake's, say) is left alone; `vim.g.msvc_compiledb_auto = false` keeps it to `:MsvcCompileDb [Configuration] [Platform]`, which also sets the configuration later rebuilds use (Debug, x64 by default).
- **cscope_maps** loads on its commands and keys, or for a tree with a `cscope.out`, instead of with every file (about 20 ms there).
- **Mason** skips a package whose runtime is not on PATH (Java, Elixir, Erlang, Julia; `lua/features/external_programs/package_runtime_requirements.lua`) and, for 7 days, one whose install failed (`stdpath("state")/mason-failed.json`), so a build that cannot work here does not rerun in every session or hold up the exit; `:MasonInstall NAME` retries at once.

### Tool paths (`lua/features/external_programs/registered_programs.lua`)

`<leader>uX` (or `:ToolPath`) lists the programs this config runs by name with the one each resolves to, and registers one by path: `stdpath("state")/tools.json` keeps the choice and `stdpath("data")/shims` one shim per program, the only directory added to PATH, at its end, so nothing beside the program comes into reach and a program already on PATH still wins. A shim is a symbolic link, on Windows a copy of `winctl` that runs the program named in `NAME.shim` with the same arguments and exit code (an `.exe` or `.com`; a `.cmd` would have cmd.exe parse the arguments again), with the program's own directory first on its PATH alone, as in the environment it ships with: MSYS2's `cscope` then finds that environment's `sort` for its `-q` index. `:ToolPath NAME PATH` registers (a relative PATH is taken from the current directory), `:ToolPath! NAME` forgets. With nothing registered it costs one stat at startup. On Windows a `.shim` may also hold a path relative to its own directory, never the current one; drive-relative, rooted, device and network paths, alternate data streams, anything but an `.exe` or `.com` on a local disk, another shim and the shim itself are refused (a shim naming a shim could loop), and a shim runs only with Neovim among its nearest ancestors (`:terminal` included). The program runs in a job that ends it with the shim, and does not run at all when that cannot be set up. A shim's failure goes to its stderr and to `winctl-shim.log` beside it, which Neovim watches through the system's change notification and shows at once; a shim or its `.shim` removed by hand is made again at the next start.

On Windows the picker also reads what the system records, on request only (`lua/features/external_programs/windows_program_discovery.lua`, one PowerShell run, under a second): the machine and user PATH in the registry, against this Neovim's (programs installed after it started; added to the session with one pick), App Paths, the install locations of installed programs with their usual bin directories (MSYS2's `cscope`, say), Visual Studio's LLVM tools through vswhere, and the winget, Scoop, Chocolatey and Cargo directories their variables name. What it finds is kept in `stdpath("state")/tool_discovery.json` and offered beside each program; nothing is registered until picked.

### Managed paths and the reset (`lua/features/maintenance/stored_data_paths.lua`, `scripts/reset_to_fresh_clone.lua`)

`<leader>uM` (or `:ManagedPaths`) lists where everything is kept, read from Neovim and the system each time rather than written down: Neovim's own directories (`stdpath()` config, data, state, log and cache; on Windows data, state and log are one, `%LOCALAPPDATA%\nvim-data`, and the cache is `%TEMP%\nvim`; on Linux `~/.local/share/nvim`, `~/.local/state/nvim`, `~/.cache/nvim`, or what `$XDG_*_HOME` and `NVIM_APPNAME` make them) with what each entry in them holds and its size (measured in the background), Neovide's settings (`$XDG_CONFIG_HOME/neovide`, else `~/.config/neovide` on Linux and macOS alike; `%APPDATA%\neovide`; or the file `NEOVIDE_CONFIG` names) and the window state it remembers (`neovide-settings.json` in `$XDG_DATA_HOME/neovide` or `~/.local/share/neovide` on Linux, `~/Library/Application Support/neovide` on macOS, `%LOCALAPPDATA%\neovide`; as Neovide's source computes them), the `compile_commands.json` files `:MsvcCompileDb` wrote, and what Neovim puts on PATH: Mason's bin, the tool shims and the MSVC environment, inside the running Neovim only. Nothing else is written: not the system or user PATH, the registry or a shell profile. Its first lines say what decided that layout: `NVIM_APPNAME`, each `XDG_*_HOME` that is set (Neovim reads them on Windows too), a Flatpak sandbox (`FLATPAK_ID`, `/.flatpak-info`: the XDG directories are then the app's, under `~/.var/app`), a Snap, an AppImage; or the defaults. `<CR>` opens a line's path, `y` copies it.

The reset goes back to a fresh clone and has no key: `:ManagedPathsReset` shows the list and asks for `reset` to be typed, quits as `:confirm qa` does, and removes every line marked `remove` once this Neovim (and the Neovide around it) has exited, by `nvim -l scripts/reset_to_fresh_clone.lua --after PID --token T`, which removes only with the one-time confirmation that prompt leaves; the next start installs the plugins, Mason's packages and the parsers again and says what was removed. It refuses while another Neovim with a UI runs. A directory is renamed before it is removed, so one a running program still holds (Windows refuses the rename) stays whole rather than half gone, and is reported. Never removed: the configuration itself (with `lazy-lock.json`), Neovide's settings link (made at installation; remove it by hand), anything outside the paths listed. Only `reset` typed at the prompt removes anything: keys already waiting (a mapping, a macro, typeahead) are set aside while it is open, there is no default or completion, and the answer is not kept in the input history. From a terminal, with every Neovim closed, `nvim -l scripts/reset_to_fresh_clone.lua` lists and asks the same; there is no flag that skips the question, and an answer from a pipe or a file is not taken.

#### Testing the layouts (`tests/stored_data_paths/`)

`tests/stored_data_paths/check.lua` holds each Neovim to the rule it follows (`$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`, `$XDG_STATE_HOME`, `$XDG_CACHE_HOME`, else `~/.config`, `~/.local/share`, `~/.local/state`, `~/.cache`, with `NVIM_APPNAME` appended; on Windows the same variables, else `%LOCALAPPDATA%` and `%TEMP%`, with `-data` for data and state), then the module: what it lists and as what, what it says decided the layout, and what a reset removes and keeps (the configuration, a directory a link points to, Neovide's settings link). Every variant runs in a throwaway root that `HOME` and every directory point into; the test refuses to run otherwise, and nothing outside the root is removed.

- `tests/stored_data_paths/run.sh [--release] [NVIM...]` on Linux and macOS: variants default, xdg, appname, appname-nested, flatpak-sim (the variables a Flatpak sets), overlap (data = configuration) and nested (configuration inside data); then the reset's question, with `reset` piped in (nothing removed) and typed into a pseudo-terminal through `script(1)` (removed; `no` keeps everything). `--release` adds the official 0.12.2 build, its SHA-256 checked against the one GitHub publishes.
- `tests/stored_data_paths/docker.sh [--engine podman|docker] [distribution...]` runs it in throwaway containers, podman first when both are installed, and stops with an error when neither is installed or the one found does not answer: Arch, Debian stable, Ubuntu (newest LTS), Fedora, Rocky Linux 10 (Neovim from EPEL), openSUSE Tumbleweed, Void, Gentoo (the slowest: binary packages from Gentoo's binhost) and Nix by default, a real Flathub sandbox (`flatpak`, needs `--privileged`) on request. Each image is the one the distribution's own project publishes, named in full from its registry (`registry.fedoraproject.org`, `registry.opensuse.org`, `ghcr.io/void-linux`, Docker Hub's `rockylinux/rockylinux`, `gentoo/stage3`, `nixos/nix` and official images), so podman never guesses one. Each installs its own Neovim with its package manager (signatures checked as it always does), creates a user, puts the configuration where a user clones it (`~/.config/nvim`) and runs `run.sh` as that user, with the release build (glibc) and `--installed`: that user's real layout, which `run.sh` refuses outside a container since its reset removes the data it finds. Containers run with `--rm`, `no-new-privileges` and a process limit, mount the repository read-only, and carry the label `org.nvim-config.test=paths`: `--clean` removes those (and only those) an interrupted run left, `--clean-images` the images this script pulled, never one that was there before.
- `tests/stored_data_paths/run.ps1` on Windows (no Flatpak variant; the typed answer needs a console).

### Open Folder and the dashboard (`lua/features/editing/open_folder.lua`, `lua/features/appearance/dashboard_header.lua`, `lua/plugins/editing/open_folder.lua`)

`o` on the dashboard, or `<leader>fo`, opens [yazi](https://yazi-rs.github.io/) in a float at the working directory. `q` makes the folder yazi is in the working directory: the folder being left gets its session saved (as persistence.nvim does on exit), its buffers close, and the new folder's session comes back if it has one, the dashboard otherwise. `Q` cancels. `<CR>` on a file opens it, with the working directory at its git root, else its folder. A modified buffer stops the switch. Without `yazi` in `PATH`, neither the entry nor the key exists.

`nvim DIR` and `neovide DIR` start the same way: in DIR, with its session or the dashboard, and no directory buffer or explorer sidebar (`:e DIR` later still opens the explorer).

Folders opened either way are remembered (newest 50, in `stdpath("state")/open_folder_history`) and listed by Projects (`p`, `<leader>fp`) beside the git roots of recent files; picking one switches like Open Folder.

The header draws the system's logo (from `/etc/os-release` on Linux and FreeBSD, by name on macOS and Windows) left of NVIM, in its brand colour, shifted to the nearest shade that reads at 3:1 against the background. An unknown system, an error or a narrow window leaves NVIM alone.

### Opening a location from other programs (`lua/features/editing/open_in_running_instance.lua`, `scripts/open-at.lua`)

A Neovim or Neovide with a UI records its RPC socket (`v:servername`) in `nvim-focus/<pid>` under `stdpath("run")` (`stdpath("state")` without `$XDG_RUNTIME_DIR`) when the UI attaches or gains focus, and removes it on exit. `nvim -l scripts/open-at.lua FILE [LINE [COLUMN]]` sends `:drop FILE` to the most recently focused live instance, puts the cursor on LINE and COLUMN (clamped) and raises the window of the nearest ancestor that owns one: Hyprland (`hyprctl`), Sway (`swaymsg`), niri, KDE Plasma 6 (`kdotool`), X11 (`xdotool`), macOS (`osascript`) and Windows (`winctl raise`, one native call for the whole lineage, else one PowerShell); GNOME on Wayland offers no way, so the window stays where it is. With no reachable instance it starts `neovide -- +LINE FILE`. Nothing listens on TCP.

heaptrack_gui, Settings → Code Navigation → Custom...: `nvim -l <home>/.config/nvim/scripts/open-at.lua %f %l %c`. heaptrack splits the command and starts it without a shell, so the path has to be absolute.

### UI & appearance

- **`spaceduck-remix`**: an unofficial derivative of [spaceduck](https://github.com/pineapplegiant/spaceduck) by Guillermo Rodriguez, hand-written in Lua on its palette with a C/C++ palette of its own; true colour, no `Normal` background in the terminal, opaque under Neovide. Its 16 terminal colours are spaceduck's kitty theme, so yazi, lazygit and `:terminal` match. `colorscheme.lua` also installs `gruvbox-material` and `kanagawa.nvim` (with its README's transparent floats and no gutter background). A colorscheme confirmed in `<leader>uC` stays the default across restarts (`stdpath("state")/colorscheme`); confirming `spaceduck-remix` clears it.
- **Terminal background**: in the TUI the terminal's own background follows `Normal` (OSC 11), so kitty's padding matches the editor; it is restored on exit and suspend, and left alone inside tmux, screen, Zellij and `:terminal` (`lua/features/appearance/terminal_background.lua`).
- **Statusline**: the full path, never shortened; an encoding/line-ending flag (`UTF-8/LF`, `UTF-8+BOM/CRLF`); after the branch, the `git describe --tags` tag (`v6.12.95`, or `v6.12.95+12` twelve commits past it), re-read after 60 s, on focus and on `:cd`, never while unfocused.
- **hlslens**: `[current/total]` beside the nearest match after `n`/`N`/`*`/`#`/`g*`/`g#` and `/`/`?`; noice's search count is off.
- **mini.files**: `<CR>` opens a file and closes the explorer, or enters a directory.
- **Snacks**: `bigfile` from 5 MiB; explorer, files and grep include hidden and gitignored files (noisy in a kernel tree); the explorer watches the disk.
- **Diagnostics**: on `CursorHold` the line's diagnostics open in a float with their source.
- **Trouble**: `<leader>cs` (symbols) and `<leader>cS` (LSP references, definitions, ...) open at the bottom like `<leader>xx`, not in a 30-column right split.
- **Discord presence**: Rich Presence over Discord's IPC socket or pipe, on by default, showing "Editing in Neovim" and the elapsed time, no file names. It borrows the public application ID and `neovim` art of andweeb/presence.nvim.
- **markview** renders Markdown; **baleia.nvim** colours ANSI escapes in the gdb console (`:BaleiaColorize` elsewhere); **lean.nvim** keeps its infoview at the bottom.

### Common Lisp, Racket and Haskell (`lua/plugins/languages/lisp.lua`, `lua/plugins/languages/haskell.lua`, `after/ftplugin/racket.lua`)

- **Common Lisp.** The `commonlisp` parser highlights `lisp` buffers. [alive-lsp](https://github.com/nobody-famous/alive-lsp) runs in SBCL (completion, hover, definition, references, symbols, formatting on `gq`/`<leader>cf`, semantic tokens); `ocicl lint` adds INFO diagnostics on read and write. `'` and `` ` `` are not auto-paired and nothing is formatted on save. `.el` files get neither server, linter nor REPL keys.
- **`scripts/alive_lsp_over_stdio.lisp`** runs alive-lsp over stdio instead of a TCP port, turns `*read-eval*` off after loading, and reshapes hover, definition, formatting and shutdown replies. It calls alive's internal `create-deps`, so re-check it before moving the pin.
- **Installing alive-lsp** (pinned to the v0.4.5 commit; the server is enabled when `sbcl` is on `PATH` and the directory holds `ocicl.csv`):

  ```sh
  mkdir -p ~/.local/share/nvim/alive-lsp && cd ~/.local/share/nvim/alive-lsp && : > ocicl.csv
  OCICL_LOCAL_ONLY=1 ocicl install git+https://github.com/nobody-famous/alive-lsp@85f118b85d1543bb7413166b6793b87975b4d439
  ```

- **REPL** (`lua/features/languages/lisp/repl.lua`): `sbcl` with `~/.sbclrc` in a bottom terminal split, started in the project root (`ocicl.csv`, `.git` or an `.asd`). Code reaches it through a temp file that `(nvim-repl:ev …)` reads and deletes, never through the pty; no socket is opened, and ocicl's `*download*` is off.
- **Racket** needs only `racket`. The `racket` parser highlights `racket` buffers, Neovim's runtime indents them, and `K` opens the local docs (`raco docs`). There is no language server: racket-langserver loads html-parsing (last release 2022) and mcfly (2016) at startup.
- **Racket REPL** (`lua/features/languages/lisp/repl.lua`): `racket -i` in a bottom terminal split, in the nearest folder with `info.rkt` or `.git`. Under `TERM=dumb` xrepl reads plain lines and saves no history; forms go through temp files that the REPL deletes after `,ld`.
- **Haskell.** [haskell-tools.nvim](https://github.com/mrcjkb/haskell-tools.nvim) (`^11`) runs haskell-language-server for Haskell and Cabal files (lspconfig's `hls` is off), with the `haskell` parser, `hlint`, and format on save through HLS's fourmolu. `~/.ghcup/bin` is appended to `PATH`, so an earlier binary of the same name wins.

### Other languages (`lua/plugins/languages/python.lua`, `elixir.lua`, `linting.lua`, `formatting.lua`, `treesitter.lua`)

- **Python**: `ty` (Mason) for types and hover; `ruff`, when on `PATH`, lints (hover off) and formats through conform.
- **Elixir**: `expert` is the only server; `elixir-ls` stays for debugging. Each session gives Expert a random cookie instead of the public `expert` one and keeps its manager on loopback; the engine still listens on every interface, but the public cookie no longer opens it.
- **Kotlin**: `ktlint` on read and save; `detekt` only where the project ships `config/detekt/detekt.yml` or `detekt.yml`. **YAML**: `yamllint` with the nearest `.yamllint*`, `$YAMLLINT_CONFIG_FILE` or `~/.config/yamllint/config`, else `relaxed` without line length.
- **Formatting**: `oxfmt` for JS/TS, JSON, CSS and HTML, `taplo` for TOML. C/C++ go through clang-format: a `.clang-format` found upward wins; without one, the buffer's indentation with function braces on their own line, other braces attached, no one-line functions and includes left in order. **Parsers**: `treesitter.lua` adds `awk`, `css`, `dockerfile`, `erlang`, `git_config`, `git_rebase`, `gitattributes`, `gitcommit`, `java`, `julia`, `kconfig`, `kotlin`, `make`, `racket`, `rust`.

### External change detection & refresh (`lua/plugins/editing/reload_on_external_change.lua`)

`:checktime` runs every 2 s while Neovim has focus and on `BufEnter`/`CursorHold`, so files rewritten meanwhile are caught: unmodified buffers reload with a notification, modified ones still raise W12. An open mini.files re-reads when a directory it shows changes on disk, unless it holds pending edits. `:FsRefresh` (`<leader>uR`) also re-scans every snacks explorer.

### ChKeys (`lua/features/appearance/keystroke_display.lua`)

Typed keys show in floats at the bottom right for 1.6 s, with `한` while the IME is in Hangul; one window per key under Neovide. Off at startup; `<leader>uK` or `:ChKeysToggle`. Terminal mode and `input()`/`inputsecret()` prompts are never shown (`excluded_modes`, `hide_cmdtypes` in `setup()`). Nothing is written to disk.

### Neovide GUI (`lua/plugins/appearance/neovide_gui.lua`, `lua/plugins/input_method/neovide_input_method.lua`)

Only under Neovide: text gamma 1.5 and contrast 1.0, 120 Hz (5 Hz idle), short cursor animation, 28 px padding (none at the bottom, where an empty cmdline row sits instead: Neovide stretches the last row into the sub-cell gap below it, which doubled the statusline), full opacity, quit confirmation, `neov-ime.nvim` and the keys below.

The font lives in `neovide/config.toml`, tuned to match kitty at scale 1: CaskaydiaCove Nerd Font Mono at 11.15 pt, SemiBold for bold, kitty's 8 px cells. `guifont` stays unset, since it would override that table and cannot name SemiBold. Text still looks slightly lighter than in kitty, which blends in linear light where Neovide blends in sRGB.

`neov-ime.nvim` draws the IME preedit in the buffer. fcitx5 answers every cursor move with an empty preedit, and neov-ime re-sets the cursor on each one, which made `$` forget the end of line on the next `j`/`k`; only an empty preedit that ends a composition reaches it now.

`neovide/config.toml` sets `fork = true`: `neovide .` typed in a terminal returns at once and the editor runs in its own session, so closing the terminal leaves it open (`&` is not needed; zsh would only lower its priority). Launched from a menu, with no terminal, Neovide never forks. `neovide --no-fork` waits as before.

`startup-message-capture = false` keeps noice in charge of the cmdline and messages. Since 0.17 Neovide advertises `ext_messages` and `ext_cmdline` until its first redraw; noice, set up inside that window, left both to the GUI, so `:` lost its popup and a startup warning appeared.

---

## Keymap reference

`<leader>` is Space (LazyVim default). These are the mappings this repo adds on top of LazyVim's.

### Kernel navigation — cscope (Normal mode, prefix `<leader>i`)

| Key | Action |
|-----|--------|
| `<leader>is` | Find this **s**ymbol |
| `<leader>ig` | Find this **g**lobal definition |
| `<leader>ic` | Find functions **c**alling this function |
| `<leader>id` | Find functions called by this function |
| `<leader>it` | Find this **t**ext string |
| `<leader>ie` | Find this **e**grep pattern |
| `<leader>if` | Find this **f**ile |
| `<leader>ii` | Find files **i**ncluding this file |
| `<leader>ia` | Find **a**ssignments to this symbol |

### Debugging (Normal mode, prefix `<leader>d`)

| Key | Action |
|-----|--------|
| `<leader>dc` | Run / continue; with no session, replay the last configuration without asking |
| `<leader>dn` | End any session and start anew, choosing configuration, executable and arguments again |
| `<leader>db` / `<leader>dB` | Toggle breakpoint / conditional breakpoint (`<Esc>` keeps the current one) |
| `<leader>dF` | Break on a function name or a `0x` address (works without `-g`) |
| `<leader>dg` | List every breakpoint (line, function and address) in a picker |
| `<leader>dC` | Run to cursor; in the disassembly, to the address under the cursor |
| `<leader>di` / `<leader>do` / `<leader>dO` | Step into / over / out; instruction granularity when there is no line table |
| `<leader>dj` / `<leader>dk` | Move down / up the call stack |
| `<leader>dP` | Pause |
| `<leader>dt` | Stop: detaches when attached, terminates a launched process |
| `<leader>dT` | Terminate for real (kills a QEMU guest) |
| `<leader>dl` | Run last configuration |
| `<leader>du` | Toggle the debug panel |
| `<leader>de` / `<leader>dw` | Evaluate under cursor / add a watch (asks in a panel); also Visual mode |
| `<leader>dr` | Toggle the debug console |
| `<leader>dR` / `<leader>dm` / `<leader>dD` | Registers / hex view / disassembly (gdb and LLDB sessions) |
| `<leader>ds` | Target panel (GDB sessions only) |
| `<leader>dq` | Pick a kbuildlab guest and attach |
| `<leader>dQ` | List the kbuildlab guests |
| `<leader>dPt` / `<leader>dPc` | Debug the Python test method / class under the cursor (python buffers) |
| `<leader>dPr` | Pick a cargo target to debug, `:RustLsp debuggables` (rust buffers) |

Hex view: `t` source, `L` layout, `w` bytes per row, `g` bytes per group, `+`/`-` rows, `]]`/`[[` page, `<CR>` follow pointer, `p`/`x`/`s` pin/unpin/switch, `e` byte order, `A` ASCII column, `N` symbol annotation, `W` width fitting, `a` auto refresh, `o` read past the guard, `r` refresh. Registers: `f` filter, `<CR>` value in the hex view. Locals+Globals: `f` filter, `<CR>` pin to Watches, `K` ask gdbtools' `addr2sym` what the address on the line is (it does not read it). Control flow: `p` back to the pc, `<CR>` source line, `+`/`-` (or `=`/`_`) detail, `H`/`J`/`K`/`L` move by block. Mappings: `<CR>` region in the hex view. `r` refreshes these panels and Target; `]p`/`[p` switch the side column; `q` closes the target report and the log.

### LSP filter (Normal mode, prefix `<leader>cF`)

| Key | Action |
|-----|--------|
| `<leader>cFf` | Exclude the current file |
| `<leader>cFd` | Exclude a path for the current buffer (the file or any ancestor directory) |
| `<leader>cFa` | Advanced add — path, server scope, action |
| `<leader>cFl` | List the decided action/source for the current buffer |
| `<leader>cFe` | Edit the rules registry |
| `<leader>cFr` | Reload rules from disk |
| `<leader>cFt` | Toggle the filter for this session |

### Misc & UI

| Key | Mode | Action |
|-----|------|--------|
| `<leader>uK` | n | Toggle the ChKeys keystroke display |
| `<leader>uR` | n | Refresh buffers and file explorers from disk (`:FsRefresh`) |
| `<leader>uB` | n | Toggle all `#if` branches (colour and LSP in inactive code) |
| `<leader>uP` | n | Toggle Discord Rich Presence |
| `<leader>uX` | n | Tool paths: what each program resolves to; register one by path |
| `<leader>ba` | n | All buffers in a picker (which-key numbers only ten under `<leader>b`); opens the pick in an editing window |
| `<leader>uM` | n | Managed paths: where Neovim, the plugins and Neovide keep what they write (the reset has no key) |
| `n` / `N` / `*` / `#` / `g*` / `g#` | n | Search as usual, with the hlslens match index shown |
| `<CR>` | n (in mini.files) | Open file and close explorer / enter directory |
| `<leader>fo` | n | Open Folder in yazi (only when `yazi` is installed) |
| `<leader>fp` | n | Projects: opened folders and git roots of recent files; picking one switches like Open Folder |

### Haskell (Normal mode, haskell buffers, `<localleader>` is `\`)

| Key | Action |
|-----|--------|
| `<localleader>e` | Evaluate every `>>>` example in comments (`:Haskell hls evalAll`) |
| `<localleader>h` | Hoogle search for the signature under the cursor; queries hoogle.haskell.org until a local `hoogle` is installed |
| `<localleader>r` / `<localleader>R` | Toggle a GHCi REPL for the package / for the current file |

### Common Lisp (Normal mode, lisp buffers except `.el`, `<localleader>` is `\`)

| Key | Action |
|-----|--------|
| `<localleader>r` | Toggle the sbcl REPL window, starting sbcl the first time |
| `<localleader>e` | Evaluate the top-level form under the cursor; in Visual mode, the selection |
| `<localleader>b` | Evaluate the whole buffer |
| `<localleader>i` | Interrupt sbcl (Ctrl-C); type `abort` in the REPL to return to the top level |
| `<localleader>q` | Quit sbcl |

### Racket (Normal mode, racket buffers, `<localleader>` is `\`)

| Key | Action |
|-----|--------|
| `<localleader>r` | Toggle the racket REPL window, starting racket the first time |
| `<localleader>e` | Evaluate the top-level form under the cursor in the REPL's namespace; in Visual mode, the selection |
| `<localleader>b` | Save the file, run it as a module and enter its namespace (`,enter`) |
| `<localleader>i` | Interrupt racket (Ctrl-C) |
| `<localleader>q` | Quit racket |

### Neovide only

| Key | Action |
|-----|--------|
| `<C-=>` / `<C-+>` | Zoom in (scale × 1.1) |
| `<C-->` | Zoom out (scale ÷ 1.1) |
| `<C-0>` | Reset zoom to 1.0 |
| `<C-S-v>` | Paste from the system clipboard (n/i/v/c/t) |

### Commands

| Command | Source | Notes |
|---------|--------|-------|
| `:DbgKernel` / `:DbgKernelEarly` | `plugins/dap.lua` | Attach to a kbuildlab guest's gdbstub; the first asks how, the second attaches in early boot with `GDBTOOLS_AUTO=1` |
| `:DbgTargets` | `plugins/dap.lua` | Report the guests kbuildlab sees on this host |
| `:DbgMemory [expr\|file]` | `plugins/dap.lua` | Open the hex view |
| `:DbgRegisters` / `:DbgMappings` | `plugins/dap.lua` | Open the register / mapping panels |
| `:DbgControlFlow` | `plugins/dap.lua` | Show the control-flow graph in the source window; again to go back |
| `:DbgSafeMem on\|off\|auto` | `plugins/dap.lua` | Guard memory reads against QEMU device-region dispatch (`auto`: kernel sessions) |
| `:DbgLayout auto\|wide\|compact` | `plugins/dap.lua` | Switch the debugger window layout |
| `:DbgLayoutReset` | `plugins/dap.lua` | Rebuild the debugger windows, leaving the session and breakpoints alone |
| `:DbgBreak [name\|0xADDR]` | `plugins/dap.lua` | Toggle a breakpoint on a function or an address, no line table needed |
| `:DbgBreakpoints` | `plugins/dap.lua` | List every breakpoint in a picker |
| `:DbgState` | `plugins/dap.lua` | Report what this session supports, and why not when it does not |
| `:DbgClose` | `plugins/dap.lua` | Close every debugger window and restore the previous layout |
| `:DbgInline [on\|off]` | `plugins/dap.lua` | Show variable values where they are used; toggles without an argument |
| `:DbgLog` | `plugins/dap.lua` | Everything the debugger reported, plus the tail of nvim-dap's log |
| `:ChKeysToggle` | `chkeys.lua` | Toggle the keystroke display |
| `:FsRefresh` | `fs_refresh.lua` | Reload changed buffers + refresh snacks explorer / mini.files |
| `:ToolPath [name [path]]` / `:ToolPath! name` | `tool_paths.lua` | Pick, prompt for or register a program by path / forget one |
| `:ManagedPaths` | `managed_paths.lua` | Where Neovim, the plugins and Neovide keep what they write, with sizes |
| `:ManagedPathsReset` | `managed_paths.lua` | Type `reset` to quit and remove what `:ManagedPaths` marks `remove` (a fresh clone); no key |
| `:MsvcCompileDb [Configuration] [Platform]` | `msvc.lua` | Windows: rebuild compile_commands.json from the nearest .sln, .slnx or .vcxproj now, and keep that configuration for the automatic rebuilds (Debug, x64 by default) |
| `:DiscordRpcToggle` / `:DiscordRpcStatus` | `discord_rpc.lua` | Toggle / report Discord Rich Presence |
| `:BaleiaColorize` | `ansi_color.lua` | Interpret ANSI escape codes in the current buffer as colours |
| `:Cscope` / `:Cs` | `cscope_maps.nvim` | cscope_maps' commands; the `<leader>i*` keys run `:Cscope find …` |

---

## Caveats

- **A QEMU gdbstub takes one client**: while Neovim is attached, another `gdb` cannot connect; use the gdb console panel.
- **Source lines, stepping and locals need `-g`** (`-g -O0` for line stepping); `<leader>dF` breaks on a symbol or address without it.
- **A QEMU user-mode stub cannot be interrupted**: `<leader>dP` does nothing, and a breakpoint change waits for the next stop.
- **Early-boot arming can take tens of seconds** (direct boots, x86 UEFI with KASLR); the session sits at the reset vector meanwhile, not hung.
- **An x86 UEFI guest with KASLR needs a QEMU monitor and two of the four hardware breakpoints.**
- **Opening a Haskell project runs its code.** HLS builds it, so Template Haskell and a custom `Setup.hs` execute. Treat untrusted repositories accordingly.
- **alive-lsp knows its own image, not your project**; the REPL is a separate SBCL (`<localleader>i` interrupts a long print).
- **An Elixir breakpoint on a line holding only a literal is never hit**, though ElixirLS reports it verified; put it on a call or a match.
- **The first Elixir debug run per Elixir/OTP version is slow**: the `elixir-ls` Mason package fetches and compiles ElixirLS through `Mix.install`.
- **`<leader>dP` waits for `timeoutlen` (300 ms) in Python and Rust buffers**, being a prefix of `<leader>dPt`/`<leader>dPc`/`<leader>dPr`.

---

## Credits

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

<!-- credits:end -->
