# nvim-config

A [LazyVim](https://www.lazyvim.org/)-based Neovim configuration tuned for **Linux kernel / C development**, with a GDB-native debugger, a per-path LSP gate, Korean input-method integration, an on-screen keystroke display, a hand-written colorscheme and a Neovide profile.

Linux is the primary target. The IME reset has Windows and macOS branches, but the kernel workflow and the Caps Lock indicator expect Linux.

---

## Highlights

- **LazyVim base** with this repo's `lua/plugins/` on top.
- **C/C++**: indentation from `.editorconfig`/`.clang-format` or the file, no autoformat; clangd, cscope and `tags` tuned for big trees.
- **Low-level highlighting** for `.S`/`.s`, inline `asm("…")`, linker scripts and device trees; man pages with highlighted code.
- **Debugger on GDB's own DAP** for userspace, QEMU user mode and Linux kernels behind a QEMU gdbstub; Python, Rust, JS/TS and Elixir use their own adapters.
- **`lsp_filter`** turns clangd (or any server) off per file or directory.
- **Korean IME integration**, **ChKeys** keystroke display, **`spaceduck`** colorscheme, **Neovide** profile.

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
| | `cscope` | Symbol navigation. |
| | `universal-ctags` | The `tags` file behind `<C-]>`. |
| **Debugging (optional)** | `gdb` **14+** | The debug adapter is GDB itself. |
| | `codelldb`, `js-debug-adapter`, `debugpy`, `elixir-ls` | The other adapters (Mason). |
| | `qemu-system-*` | Bare-metal and QEMU-user targets. |
| | [kbuildlab](https://github.com/yugeun-song/kbuildlab) | Kernel targets: guests, gdb and session come from `kbuildlab attach --json`; without it kernel debugging is off. |
| | [gdbtools](https://github.com/yugeun-song/gdbtools) (optional) | Early-boot kernel symbols, `cfgjson` and `addr2sym`, sourced into each gdb when installed. |
| | `<triple>-gdb` (optional) | Preferred per target, else `gdb-multiarch` or an all-targets `gdb`; one whose Python fails to start is skipped, with a notice. `vim.g.dbg_gdb` names one (a string, or a table by arch); a kernel session runs kbuildlab's (`GDB=` in tree.conf, or `$KBL_GDB`). gdb 14 or newer (`gdb -i dap`). |
| | `qemu-<arch>` usermode (optional) | Foreign-architecture userspace (`qemu-user`). |
| | `/usr/<triple>` cross runtime (optional) | Sysroot for dynamic cross binaries, when present. |
| **Common Lisp (optional)** | `sbcl`, `ocicl` | alive-lsp, REPL, lint. |
| **Haskell (optional)** | `ghc`, `cabal`, `haskell-language-server`, `hlint` from [GHCup](https://www.haskell.org/ghcup/) | `~/.ghcup/bin` joins the end of `PATH`. |
| **Lean (optional)** | `elan` | The project's Lean toolchain (not Mason). |
| **Python (optional)** | `ruff` | Lint and format beside `ty` (Mason). |
| **Korean IME (optional)** | `fcitx5` + `fcitx5-remote` | IME reset and indicator. |
| **Caps Lock indicator (optional)** | Linux sysfs LED node | `/sys/class/leds/input*::capslock/brightness`. |
| **GUI (optional)** | [Neovide](https://neovide.dev/), `CaskaydiaCove Nerd Font Mono` | The GUI profile. |
| | `wl-clipboard` or `xclip` | `+` register for the GUI paste key. |
| **Discord presence (optional)** | Discord desktop client | Linux only. |
| **Editing the config (optional)** | `lua-language-server`, `stylua` | From Mason. |
| **Terminal (optional)** | kitty / WezTerm / foot / ghostty / rio | kitty keyboard protocol for ChKeys. |

> For the kernel workflow, generate the index files from the source tree: `make C=2 compile_commands.json` (or `scripts/clang-tools/gen_compile_commands.py`), `make cscope`, `make tags`.

---

## Installation

Neovim reads `$XDG_CONFIG_HOME/nvim` (default `~/.config/nvim`). Move an existing config aside, clone and link (or clone straight into `~/.config/nvim`):

```zsh
mv ~/.config/nvim ~/.config/nvim.bak 2>/dev/null
git clone https://github.com/yugeun-song/nvim-config.git ~/workspace/nvim-config
ln -s ~/workspace/nvim-config ~/.config/nvim
nvim
```

To try it beside your own config, give it a separate `NVIM_APPNAME` (Neovim then uses `~/.config/test-nvim`, `~/.local/share/test-nvim`, …):

```zsh
git clone https://github.com/yugeun-song/nvim-config.git ~/.config/test-nvim
NVIM_APPNAME=test-nvim nvim
```

The first start installs lazy.nvim, the plugins, the parsers and the Mason packages from `lua/plugins/mason.lua` (into `~/.local/share/nvim/mason/`). Check with `:Lazy` and `:LazyHealth`, then restart once. Update plugins with `:Lazy update` (commits are recorded in `lazy-lock.json`) and the config with `git pull`.

---

## Repository structure

```
nvim-config/
├── init.lua                  # → require("config.lazy")
├── lazy-lock.json            # plugin lockfile
├── lazyvim.json              # LazyVim extras (mini.files)
├── .neoconf.json             # lua_ls settings
├── stylua.toml               # StyLua style
├── after/
│   ├── ftplugin/
│   │   ├── lisp.lua          # Lisp buffer settings, REPL keys
│   │   └── man.lua           # man windows, man_code passes
│   └── queries/              # Tree-sitter injections:
│       ├── asm/injections.scm #   C in .S/.s directives
│       ├── c/injections.scm  #   assembly in asm("…")
│       └── cpp/injections.scm #   same, for cpp headers
├── colors/spaceduck.lua      # the colorscheme
├── scripts/alive-lsp-stdio.lisp # alive-lsp launcher
└── lua/
    ├── chkeys.lua            # keystroke display
    ├── lisp_repl.lua         # sbcl REPL
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
    │   ├── keymaps.lua       # ChKeys
    │   └── autocmds.lua      # C indent, cscope, tagfunc, prose
    ├── man_code/             # man page highlighting (code, structure)
    ├── lsp_filter/           # per-path LSP gating (init, rules, util)
    └── plugins/              # one spec per plugin, named for it:
        ├── dap.lua, dap_languages.lua # nvim-dap, GDB adapters, keys; other debuggers
        ├── clangd.lua, cscope.lua, asm.lua # C workflow and low-level highlighting
        ├── treesitter.lua, formatting.lua, linting.lua # parsers, oxfmt/taplo, ktlint/detekt/yamllint
        ├── python.lua, elixir.lua, haskell.lua, lisp.lua, lean.lua # per-language setup
        ├── im_control.lua, imstate.lua # langmap, IME reset, statusline state
        ├── lualine.lua, git_tag.lua, hlslens.lua, noice.lua # statusline, tag, search index
        ├── snacks.lua, mini-files.lua, markview.lua, diagnostics.lua # pickers, explorer, markdown, floats
        ├── colorscheme.lua, neovide.lua, neovide-ime.lua # spaceduck, GUI
        ├── ansi_color.lua, discord_rpc.lua, fs_refresh.lua # baleia, presence, reload
        └── lsp_filter.lua, mason.lua # filter keys, Mason packages
```

## Features in detail

### Base (`init.lua`, `lua/config/lazy.lua`, `lua/config/options.lua`)

lazy.nvim (stable) is cloned on first run and imports LazyVim plus `lua/plugins/`. Plugins load at startup and track their latest commit, with silent update checks. Options: absolute line numbers, `tags = "./tags;,tags;"`, a bar cursor in Insert mode, no modelines, no swap files (so no swap recovery), `h`/`l`/arrows wrap across lines, node/perl/ruby providers off.

### Prose buffers (`lua/config/autocmds.lua`)

`text`, `plaintex`, `typst`, `gitcommit` and `markdown` buffers wrap but keep spell off; `<leader>us` toggles it, and `spelllang = en,cjk` leaves Hangul, Han and kana alone. LSP clients are detached from `claude-prompt-*.md`, the file Claude Code opens on `Ctrl+G`.

### Linux kernel C workflow (`lua/config/autocmds.lua`, `lua/plugins/clangd.lua`, `lua/plugins/cscope.lua`)

- **Indentation.** A `.clang-format` found upward sets it (`IndentWidth`, `UseTab`, `TabWidth` or the `BasedOnStyle` default); a project `.editorconfig` wins. With neither, a buffer whose first 2000 lines start more often with a tab than with two spaces gets 8-column tabs, else 4 spaces. Existing whitespace is never rewritten; `list` is on and autoformat off.
- **clangd**: `--background-index --clang-tidy --completion-style=detailed --header-insertion=never --pch-storage=disk --background-index-priority=background --limit-results=200 --limit-references=2000 --log=error -j=<half the CPUs>`, inlay hints off.
- **cscope**: `cscope_maps.nvim` with Telescope under `<leader>i`; reading a `*.c`/`*.h`/`*.S` file adds the nearest `cscope.out` above it, once per session.
- **`<C-]>`**: the LSP `tagfunc` is cleared in C/C++ buffers, so it jumps through `tags` (`make tags`).

### Low-level highlighting (`lua/plugins/asm.lua`, `after/queries/`)

In `.S`/`.s`, `#` lines starting with a preprocessor directive are parsed as C, while a `#` comment after an instruction stays a comment (via the `#at-line-start?` predicate in `asm.lua`, which the query needs). In C/C++, including kernel headers detected as `cpp`, each string of an `asm("…")` body is parsed as assembly. `.S`/`.s`/`.sx` are pinned to `asm`; `*.lds`/`*.ld`/`*.lds.S` use `linkerscript`, `*.dts`/`*.dtsi` `devicetree`. This is injection, not preprocessing: `#if 0` bodies stay highlighted, and `linkerscript` leaves `#` lines plain.

### Man pages (`after/ftplugin/man.lua`, `lua/man_code/`)

`:Man` buffers keep the global `number`, `relativenumber` and `signcolumn`. Code blocks are parsed with the C grammar (sections 0, 2 to 5, 7, 9 and suffixes such as `3p`; another suffix names its grammar), skipping prose, within 100 ms per page. Headings, options and `name(section)` references are re-marked above roff's bold, so the `man*` highlight groups show.

### Debugging (`lua/plugins/dap.lua`, `lua/dbg/`)

C, C++ and assembly are debugged by GDB itself (`gdb -i dap`), so `~/.gdbinit`, pwndbg and other GDB Python tooling load as usual. Other languages use their own adapters (`lua/plugins/dap_languages.lua`):

| Language | Debug support | What it brings |
|---|---|---|
| C / C++ / asm | `gdb -i dap` | The panels below, QEMU user mode, gdbtools |
| Linux Kernel | `gdb -i dap` (`gdb_kernel`) | The same, plus kernel attach |
| Python | [`nvim-dap-python`](https://github.com/mfussenegger/nvim-dap-python) on `debugpy` | Its configurations, the test under the cursor |
| Rust | [`rustaceanvim`](https://github.com/mrcjkb/rustaceanvim) on `codelldb` | `:RustLsp debuggables`, LLDB's Rust formatters |
| JavaScript / TypeScript | `js-debug-adapter` | `pwa-node`/`-chrome`/`-msedge`; `.ts` on Node's type stripping, or `tsx`/`ts-node` if installed |
| Elixir | [ElixirLS](https://github.com/elixir-lsp/elixir-ls)'s adapter (`mix_task`) | `mix test` and `mix run` |

`.vscode/launch.json` is read for every language; Julia and Java have no debugger. The rest applies to `gdb` and `gdb_kernel` sessions; others get plain `nvim-dap-view`.

- **Programs.** Launch, launch to `main`, attach by PID, *Run on QEMU user* (starts `qemu-<arch> -g <port>` with `-L /usr/<triple>`, stopped at `_start`; x86_64, aarch64, riscv64, arm) and *Attach to a QEMU user gdbstub*. Executable and shell-quoted arguments are remembered; `<leader>dc` with no session replays the last run, `<leader>dn` asks again. A cross target gets `vim.g.dbg_gdb`, else the first `<triple>-gdb` or `gdb-multiarch` whose Python starts, else an all-targets `gdb`; with none the session does not start and says why. A QEMU user process that fails to start is reported and no gdb is attached. gdbtools is sourced from `$GDBTOOLS_PATH` or the checkout its `setup.sh` recorded, and a stated location that is wrong is an error, not a search.
- **Kernel targets.** `<leader>dq` lists the guests `kbuildlab attach --list --json` reports, with their tree, boot mode, KASLR and whether a debugger holds the stub (a busy stub is refused); a guest kbuildlab did not start (no tree recorded) is attached by choosing its registered tree (listed by ID, arch, release and source) and its port. `<leader>dQ` shows the list. It then asks: attach where the kernel is (warning when KASLR is on or unknown), or early boot (`:DbgKernelEarly` skips the question). Early boot exports `GDBTOOLS_AUTO=1`, runs `kearly on` then `kearly bootbreak arm` after the attach stop, continues to the first `head.S` instruction and reports `kearly status`; `kearly kaslr auto` is left to you.
- **Kernel adapter.** Each start asks `kbuildlab attach TREE --port N --json` for the session, so a replayed configuration follows a guest restarted in another boot mode: the gdb, its `-iex` lines (the tree's own `scripts/gdb` trusted, gdb in the kernel source), gdbtools, the `GDBTOOLS_*` environment, the vmlinux, the target, a u-boot ELF to load and QEMU's pid. Nothing of the tree is re-derived here. nvim-dap waits 60 s before calling gdb unresponsive. A vanished QEMU disconnects the session but leaves the panels; a lost connection gdb reports is announced too.
- **All-stop remotes.** A remote target takes no command while it runs: a breakpoint change is held, the target interrupted unseen by nvim-dap, the change sent, the target resumed. If it does not stop within 2 s, the change waits for its next stop (said once).
- **Stopping.** `<leader>dt` detaches an attached target (interrupting it first if it runs) and terminates a launched one; `<leader>dT` kills, ending a QEMU guest. After a disconnect the session closes once gdb has exited (up to 3 s); quitting Neovim treats every session the same way, then kills any leftover `gdb -i dap`. Requests made while gdb starts the target wait for its launch or attach answer.
- **Breakpoints.** Line breakpoints are allowed without DWARF (a library may carry it); refused ones are reported with gdb's message, unbound ones with the likely reason. `<leader>dF` breaks on a function or `0x` address with no line table. Pending breakpoints keep one sign each, and a breakpoint gdb makes itself (the stop-at-main `tbreak`) never replaces yours on the same line.
- **Run to cursor and stepping.** `<leader>dC` runs to the source line or disassembly address under the cursor through gdb's own one-shot breakpoint, so your breakpoints stay set (nvim-dap's run-to-cursor would clear them all). The frame selection returns to frame 0 after nvim-dap picks a caller with source, so every view agrees; without source, steps go by instruction and the disassembly is shown.
- **Panels** (`nvim-dap-view` tabs; the label's letter switches): Scopes, Locals+Globals (frame and file variables, `static` included, optimised-out ones tagged `opt`), Watches, Registers (`<symbol+offset>`, change marks), Memory (hex view of an expression, a physical address or a file, 8 KiB per window), Mappings (pwndbg's `vmmap`), Control flow (gdbtools' `cfgjson`; `:DbgControlFlow` puts it in the source window), Disassembly (pc highlight, connector to a taken branch), Call stack, Breakpoints, Target, gdb console and Output. Values also show at the end of lines using them (`:DbgInline off`).
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

### `lsp_filter` — per-path LSP gating (`lua/lsp_filter/`, `lua/plugins/lsp_filter.lua`)

Turns servers off for generated or vendored subtrees. A rule matches a path prefix (`within`) or segment (`contains`), targets `clangd` unless `<leader>cFa` picks all servers or a list, and detaches the client (`disable`) or hides its diagnostics (`diagnostics_off`). Rules live in `~/.local/share/nvim/lsp_filter/rules.json`, outside every repository: one line of JSON, written atomically (never through a symlink), reloaded on save. Marker files (`.nvim-lsp-filter.json`) need `setup({ markers_enabled = true })`.

| Want to… | Do this |
|----------|---------|
| Turn clangd off for a directory | Open a file in it, `<leader>cFd`, pick the directory |
| Toggle the whole filter off for now | `<leader>cFt` (session only) |
| Remove a rule permanently | `<leader>cFe` → delete its object from `rules` → `:w` |

### Korean input-method integration (`lua/plugins/im_control.lua`, `lua/plugins/imstate.lua`)

`langmap` maps Dubeolsik jamo to their QWERTY keys for Normal mode. On `InsertLeave` and `FocusGained` the IME is set to English (`fcitx5-remote -c`, `im-select.exe` or `issw`), never to Korean; outside Neovide, foot's IME mode sequence keeps the IME on only in Insert mode. The statusline shows `󰬈 CAPS` (LED read every 200 ms) and `한`, or `EN`/`en` following Caps Lock (`fcitx5-remote -n` on mode, focus and idle events, plus every second), each only when its backend exists; `vim.g.caps_state` and `vim.g.im_state` hold the same.

### UI & appearance

- **`spaceduck`**: hand-written, true colour, with a C/C++ palette; no `Normal` background in the terminal, opaque under Neovide. Its `vim.g.spaceduck_lualine` theme is unused (the statusline keeps LazyVim's `auto`). `colorscheme.lua` also installs `noctis.nvim`, `lush.nvim` and `gruvbox-material` as alternates.
- **Statusline**: the full path, never shortened; an encoding/line-ending flag (`UTF-8/LF`, `UTF-8+BOM/CRLF`); after the branch, the `git describe --tags` tag (`v6.12.95`, or `v6.12.95+12` twelve commits past it), cached 10 s per repository.
- **hlslens**: `[current/total]` beside the nearest match after `n`/`N`/`*`/`#`/`g*`/`g#` and `/`/`?`; noice's search count is off.
- **mini.files**: `<CR>` opens a file and closes the explorer, or enters a directory.
- **Snacks**: `bigfile` from 5 MiB; explorer, files and grep include hidden and gitignored files (noisy in a kernel tree); the explorer watches the disk.
- **Diagnostics**: on `CursorHold` the line's diagnostics open in a float with their source.
- **Discord presence**: Rich Presence over Discord's IPC socket, on by default on Linux, showing "Editing in Neovim" and the elapsed time, no file names.
- **markview** renders Markdown; **baleia.nvim** colours ANSI escapes in the gdb console (`:BaleiaColorize` elsewhere); **lean.nvim** keeps its infoview at the bottom.

### Common Lisp and Haskell (`lua/plugins/lisp.lua`, `lua/plugins/haskell.lua`)

- **Common Lisp.** The `commonlisp` parser highlights `lisp` buffers. [alive-lsp](https://github.com/nobody-famous/alive-lsp) runs in SBCL (completion, hover, definition, references, symbols, formatting on `gq`/`<leader>cf`, semantic tokens); `ocicl lint` adds INFO diagnostics on read and write. `'` and `` ` `` are not auto-paired and nothing is formatted on save. `.el` files get neither server, linter nor REPL keys.
- **`scripts/alive-lsp-stdio.lisp`** runs alive-lsp over stdio instead of a TCP port, turns `*read-eval*` off after loading, and reshapes hover, definition, formatting and shutdown replies. It calls alive's internal `create-deps`, so re-check it before moving the pin.
- **Installing alive-lsp** (pinned to the v0.4.5 commit; the server is enabled when `sbcl` is on `PATH` and the directory holds `ocicl.csv`):
  ```sh
  mkdir -p ~/.local/share/nvim/alive-lsp && cd ~/.local/share/nvim/alive-lsp && : > ocicl.csv
  OCICL_LOCAL_ONLY=1 ocicl install git+https://github.com/nobody-famous/alive-lsp@85f118b85d1543bb7413166b6793b87975b4d439
  ```
- **REPL** (`lua/lisp_repl.lua`): `sbcl` with `~/.sbclrc` in a bottom terminal split, started in the project root (`ocicl.csv`, `.git` or an `.asd`). Code reaches it through a temp file that `(nvim-repl:ev …)` reads and deletes, never through the pty; no socket is opened, and ocicl's `*download*` is off.
- **Haskell.** [haskell-tools.nvim](https://github.com/mrcjkb/haskell-tools.nvim) (`^11`) runs haskell-language-server for Haskell and Cabal files (lspconfig's `hls` is off), with the `haskell` parser, `hlint`, and format on save through HLS's fourmolu. `~/.ghcup/bin` is appended to `PATH`, so an earlier binary of the same name wins.

### Other languages (`lua/plugins/python.lua`, `elixir.lua`, `linting.lua`, `formatting.lua`, `treesitter.lua`)

- **Python**: `ty` (Mason) for types and hover; `ruff`, when on `PATH`, lints (hover off) and formats through conform.
- **Elixir**: `expert` is the only server; `elixir-ls` stays for debugging. Each session gives Expert a random cookie instead of the public `expert` one and keeps its manager on loopback; the engine still listens on every interface, but the public cookie no longer opens it.
- **Kotlin**: `ktlint` on read and save; `detekt` only where the project ships `config/detekt/detekt.yml` or `detekt.yml`. **YAML**: `yamllint` with the nearest `.yamllint*`, `$YAMLLINT_CONFIG_FILE` or `~/.config/yamllint/config`, else `relaxed` without line length.
- **Formatting**: `oxfmt` for JS/TS, JSON, CSS and HTML, `taplo` for TOML. **Parsers**: `treesitter.lua` adds `awk`, `css`, `dockerfile`, `erlang`, `git_config`, `git_rebase`, `gitattributes`, `gitcommit`, `java`, `julia`, `kconfig`, `kotlin`, `make`, `rust`.

### External change detection & refresh (`lua/plugins/fs_refresh.lua`)

`:checktime` runs every 2 s and on `BufEnter`/`CursorHold`, so files rewritten while Neovim keeps focus are caught: unmodified buffers reload with a notification, modified ones still raise W12, and an open mini.files re-reads unless it holds pending edits. `:FsRefresh` (`<leader>uR`) also re-scans every snacks explorer.

### ChKeys (`lua/chkeys.lua`)

Typed keys show in floats at the bottom right for 1.6 s, with `한` while the IME is in Hangul; one window per key under Neovide. Off at startup; `<leader>uK` or `:ChKeysToggle`. On kitty, WezTerm, foot, ghostty and rio the kitty keyboard protocol is enabled at startup, display on or off. Nothing is written to disk.

### Neovide GUI (`lua/plugins/neovide.lua`, `lua/plugins/neovide-ime.lua`)

Only under Neovide: `CaskaydiaCove_Nerd_Font_Mono:h12:w-1`, 120 Hz (5 Hz idle), short cursor animation, 28 px padding, full opacity, quit confirmation, `neov-ime.nvim` and the keys below.

`neov-ime.nvim` draws the IME preedit in the buffer. fcitx5 answers every cursor move with an empty preedit, and neov-ime re-sets the cursor on each one, which made `$` forget the end of line on the next `j`/`k`; only an empty preedit that ends a composition reaches it now.

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
| `<leader>dR` / `<leader>dm` / `<leader>dD` | Registers / hex view / disassembly (GDB sessions only) |
| `<leader>ds` | Target panel (GDB sessions only) |
| `<leader>dq` | Pick a QEMU gdbstub and attach |
| `<leader>dQ` | Report every debug target found on this host, with the evidence |
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
| `<leader>uD` | n | Toggle Discord Rich Presence |
| `n` / `N` / `*` / `#` / `g*` / `g#` | n | Search as usual, with the hlslens match index shown |
| `<CR>` | n (in mini.files) | Open file and close explorer / enter directory |

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
| `:DiscordRpcToggle` / `:DiscordRpcStatus` | `discord_rpc.lua` | Toggle / report Discord Rich Presence |
| `:BaleiaColorize` | `ansi_color.lua` | Interpret ANSI escape codes in the current buffer as colours |
| `:Cscope` / `:Cs` | `cscope_maps.nvim` | cscope_maps' commands; the `<leader>i*` keys run `:Cscope find …` |

---

## Caveats

- **A QEMU gdbstub takes one client.** While Neovim is attached, a separate `gdb` cannot connect, and vice versa; use the gdb console panel.
- **Your own source lines and stepping need `-g`.** A line breakpoint set without DWARF binds only where a library carries it; `<leader>dF` breaks on a symbol or address regardless. Build with `-g -O0` for line stepping and locals.
- **A QEMU user-mode stub cannot be interrupted.** `<leader>dP` does nothing there, and a breakpoint changed while the program runs takes effect at its next stop.
- **Early-boot arming takes seconds, sometimes tens**, longest where the entry must be found first (direct boots, x86 UEFI with KASLR). The session looks stopped at the reset vector meanwhile; it is not hung.
- **An x86 UEFI guest with KASLR on needs a QEMU monitor and two of x86's four hardware breakpoints**, one for each copy of the image the firmware keeps; gdbtools finds the image through the monitor.
- **Opening a Haskell project runs its code.** HLS builds it, so Template Haskell and a custom `Setup.hs` execute. Treat untrusted repositories accordingly.
- **alive-lsp knows its own image, not your project**; project names come from document symbols, Tree-sitter and buffer completion. The REPL is a separate SBCL; a huge result keeps it busy until printed (`<localleader>i` interrupts).
- **An Elixir breakpoint on a line holding only a literal is never hit**, though ElixirLS reports it verified; put it on a call or a match.
- **The first Elixir debug run per Elixir/OTP version is slow**: the `elixir-ls` Mason package fetches and compiles ElixirLS through `Mix.install`.
- **`<leader>dP` waits for `timeoutlen` (300 ms) in Python and Rust buffers**, being a prefix of `<leader>dPt`/`<leader>dPc`/`<leader>dPr`.

---

## Credits

- **[spaceduck](https://github.com/pineapplegiant/spaceduck)** by *pineapplegiant* — MIT License, "Copyright (c) 2020 pineapplegiant". `colors/spaceduck.lua` is an independent Neovim/Lua re-implementation reusing the palette and name; the upstream author explicitly welcomes ports.
- Built on **[LazyVim](https://github.com/LazyVim/LazyVim)** and **[lazy.nvim](https://github.com/folke/lazy.nvim)** by *folke*.
- Notable third-party plugins: [cscope_maps.nvim](https://github.com/dhananjaylatkar/cscope_maps.nvim), [nvim-dap](https://github.com/mfussenegger/nvim-dap), [nvim-dap-view](https://github.com/igorlfs/nvim-dap-view), [nvim-hlslens](https://github.com/kevinhwang91/nvim-hlslens), [baleia.nvim](https://github.com/m00qek/baleia.nvim), [lean.nvim](https://github.com/Julian/lean.nvim), [haskell-tools.nvim](https://github.com/mrcjkb/haskell-tools.nvim), [alive-lsp](https://github.com/nobody-famous/alive-lsp), [markview.nvim](https://github.com/OXY2DEV/markview.nvim), [mini.nvim](https://github.com/nvim-mini/mini.nvim), [snacks.nvim](https://github.com/folke/snacks.nvim), [noice.nvim](https://github.com/folke/noice.nvim), [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim), and [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).
