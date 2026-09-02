# nvim-config

A [LazyVim](https://www.lazyvim.org/)-based Neovim configuration tuned for **Linux kernel / C development**, with a few personal extras: a custom per-path LSP gate, Korean input-method integration, an on-screen keystroke display, a hand-written colorscheme, and Neovide GUI settings.

The config is primarily targeted at Linux. Several features (the Korean IME reset, the Windows/macOS branches) are cross-platform, but the kernel workflow, the Caps Lock indicator, and the GUI font expect a Linux desktop.

---

## Highlights

- **LazyVim base.** Plugins are managed by [lazy.nvim](https://github.com/folke/lazy.nvim); the LazyVim distribution is imported as the foundation, and everything under `lua/plugins/` layers on top.
- **C/C++ indentation.** C/C++ buffers indent with 4 spaces (`expandtab`), show whitespace, and have autoformat disabled so sources are never reflowed on save.
- **clangd, cscope & tags wired for big trees.** clangd runs with kernel-friendly flags and dynamic parallelism; cscope databases auto-load; `<C-]>` is redirected to the `tags` file instead of LSP.
- **Low-level / cpp-preprocessed highlighting.** Kernel-style `.S`/`.s` assembly gets the C grammar Tree-sitter-injected into its `#` directive lines (so `#define`/`#include`/`#ifdef` and macro names read as C, not flat comments); inline `asm("…")` bodies inside C/C++ get the assembly grammar injected; `.S`/`.s` are pinned to GNU-as (avoiding the `vmasm` fallback on `.macro` files); linker scripts (`.lds`/`.ld`, and cpp-preprocessed `.lds.S` like `vmlinux.lds.S`) use the `linkerscript` parser; and device trees (`.dts`/`.dtsi`) use `devicetree`.
- **Debugger built on GDB's own DAP.** `nvim-dap` drives `gdb -i dap` (GDB 14+ speaks the Debug Adapter Protocol natively), so userspace C/C++, a foreign-architecture userspace binary under a QEMU user-mode gdbstub, and cross-architecture Linux Kernel debugging against a QEMU gdbstub all work without a third-party adapter. Rust picks between `codelldb`, `lldb-dap` and `gdb`; JavaScript/TypeScript and Python light up when their adapters are installed. For a GDB session it adds panels for registers, a two-column locals/globals view, a configurable hex view, memory mappings and target queries on top of `nvim-dap-view`; other languages keep nvim-dap-view's own views.
- **Custom `lsp_filter` module.** Disable clangd (or any server) per file/directory via persisted rules — useful for excluding noisy generated files from a kernel tree.
- **Korean IME integration.** A Dubeolsik → QWERTY `langmap` keeps Normal-mode commands working while the OS IME is in Hangul, the IME auto-resets to English on leaving Insert mode, and the statusline shows live fcitx5 / Caps Lock state.
- **ChKeys.** A built-in keystroke caster for screencasts/demos.
- **`spaceduck` colorscheme + Neovide profile.** A hand-written theme (transparent in the terminal, opaque under Neovide) plus a complete Neovide GUI setup.

---

## Requirements

| Group | Tool | Why |
|-------|------|-----|
| **Core (required)** | Neovim **0.10+** | The config uses `vim.uv`, `vim.fs.joinpath`, and other recent APIs. |
| | `git` | Bootstraps lazy.nvim on first launch and clones plugins; also queried for the statusline tag component. |
| | C compiler + `make` | Treesitter parsers are compiled locally. |
| | Network access | Needed on the first launch to fetch lazy.nvim and plugins. |
| **Search / UI (recommended)** | `ripgrep` (`rg`), `fd` | Backends for the Snacks picker / grep. |
| | A **Nerd Font** | Icons, statusline glyphs, the Caps Lock glyph, markview rendering. |
| **C / kernel workflow** | `clangd` | C/C++ language server (launched with kernel-friendly flags). |
| | `cscope` | Symbol navigation; databases are auto-loaded. |
| | `universal-ctags` | Generates the `tags` file that `<C-]>` jumps through. |
| **Debugging (optional)** | `gdb` **14+** | The debug adapter is GDB itself (`gdb -i dap`). Older GDB has no DAP interpreter. |
| | `lldb-dap` | Adapter used for Rust; ships with LLVM. |
| | `codelldb`, `js-debug-adapter`, `debugpy` (optional) | Installed through Mason. Each language's configurations appear only when its adapter is actually present, so the picker never offers something that cannot start. |
| | `qemu-system-*` | Only for the kernel/bare-metal workflow; the gdbstub is what Neovim attaches to. |
| | `<triple>-gdb` (optional) | `aarch64-linux-gnu-gdb`, `riscv64-linux-gnu-gdb`, … are preferred per target architecture when present; a multiarch-built `gdb` is used otherwise. |
| | `qemu-<arch>` usermode (optional) | `qemu-aarch64`, `qemu-riscv64`, `qemu-x86_64`, … (package `qemu-user`) run a foreign-arch userspace binary under a gdbstub, for the cross-arch usermode configs. |
| | `/usr/<triple>` cross runtime (optional) | e.g. `/usr/aarch64-linux-gnu` — a dynamically linked cross binary's `ld.so` and libraries; auto-detected, unneeded for a static binary. |
| **Korean IME (optional)** | `fcitx5` + `fcitx5-remote` | IME auto-reset and the Hangul/English statusline indicator. |
| **Caps Lock indicator (optional)** | Linux sysfs LED node | `/sys/class/leds/input*::capslock/brightness`. |
| **GUI (optional)** | [Neovide](https://neovide.dev/) | GUI front-end; this config has a dedicated profile for it. |
| | `CaskaydiaCove Nerd Font Mono` | The GUI font Neovide uses (`guifont`). |
| | `wl-clipboard` or `xclip` | Backs the `+` register for the GUI paste mapping. |
| **Editing the config (optional)** | `lua-language-server` (`lua_ls`), `stylua` | Lua completion/types and formatting for the config itself. |
| **Terminal (optional)** | kitty / WezTerm / foot / ghostty / rio | A terminal that supports the kitty keyboard protocol, for full ChKeys modifier capture and `Ctrl`-symbol keys. |

> For the kernel workflow you typically generate the index files from the source tree itself, e.g. `make C=2 compile_commands.json` (or `scripts/clang-tools/gen_compile_commands.py`), `make cscope`, and `make tags`.

---

## Installation

Neovim loads its configuration from the directory named **`nvim`** inside `$XDG_CONFIG_HOME` (which defaults to `~/.config`). So the config must live at `~/.config/nvim` — the **last path component has to be `nvim`**, regardless of how it gets there. The methods below differ only in *how* that directory comes to point at this repository.

### 0. Back up any existing config

```zsh
# Move anything already there out of the way first
mv ~/.config/nvim ~/.config/nvim.bak 2>/dev/null
# Optional: also stash the generated plugin/state/cache dirs for a clean slate
mv ~/.local/share/nvim ~/.local/share/nvim.bak 2>/dev/null
mv ~/.local/state/nvim ~/.local/state/nvim.bak 2>/dev/null
mv ~/.cache/nvim       ~/.cache/nvim.bak       2>/dev/null
```

### Method A — symbolic link (recommended; this is the current setup)

Keep the repository wherever you do your work and symlink it into place. Git operations then happen in your workspace instead of buried under `~/.config`.

```zsh
git clone https://github.com/yugeun-song/nvim-config.git ~/workspace/nvim-config
ln -s ~/workspace/nvim-config ~/.config/nvim
```

`~/.config/nvim` is now a symlink that resolves to the repo, so Neovim reads it normally while you edit/commit from `~/workspace/nvim-config`.

### Method B — clone directly as the config directory

If you don't need the repo anywhere else, clone it straight into the config path. The clone **destination must be named `nvim`**:

```zsh
git clone https://github.com/yugeun-song/nvim-config.git ~/.config/nvim
# add --depth=1 for a shallow clone if you don't need history
```

If you set `XDG_CONFIG_HOME` to a non-default location, clone into `"$XDG_CONFIG_HOME/nvim"` instead.

### Method C — clone elsewhere, then move or copy into place

Clone to a temporary spot, then relocate (or copy) it so the final directory is `~/.config/nvim`:

```zsh
git clone https://github.com/yugeun-song/nvim-config.git /tmp/nvim-config
mv /tmp/nvim-config ~/.config/nvim        # relocate it, or…
cp -r /tmp/nvim-config ~/.config/nvim     # …keep a copy at the source too
```

The destination directory must still be named `nvim`. Because `.git/` travels along, `~/.config/nvim` remains a working clone you can `git pull` later.

### Optional — try it without touching your real config (`NVIM_APPNAME`)

`NVIM_APPNAME` makes Neovim read `~/.config/<name>` and use `~/.local/share/<name>` etc., leaving your existing `~/.config/nvim` completely untouched — ideal for a test drive:

```zsh
git clone https://github.com/yugeun-song/nvim-config.git ~/.config/test-nvim
NVIM_APPNAME=test-nvim nvim
```

### First launch

1. Run `nvim`. On the very first start it clones lazy.nvim into `~/.local/share/nvim/lazy/` and installs every plugin — let it finish.
2. Run `:Lazy` to watch/complete the install, then `:LazyHealth` (or `:checkhealth`) to confirm external tools (`rg`, `fd`, `clangd`, `cscope`, a Nerd Font, …) are detected.
3. Treesitter parsers compile on demand (a C compiler must be present).
4. Quit and reopen once so eager-loaded plugins and the `spaceduck` colorscheme settle in.

### Updating

- **Plugins:** `:Lazy update`. Versions are pinned in `lazy-lock.json`. Note this config tracks the *latest commit* of each plugin (`defaults.version = false`) and silently checks for updates in the background (`checker.enabled = true`, `checker.notify = false`).
- **Config:** `git -C ~/workspace/nvim-config pull` (Method A) or `git -C ~/.config/nvim pull` (Methods B/C).

### Mason packages

Mason installs into `~/.local/share/nvim/mason/`, outside this repository, so a fresh clone starts without any of its packages. `lua/plugins/mason.lua` lists the packages every machine needs in `ensure_installed`; LazyVim installs the missing ones on first launch.

---

## Repository structure

```
nvim-config/
├── init.lua                  # entry point → require("config.lazy")
├── lazy-lock.json            # plugin version lockfile
├── lazyvim.json              # enabled LazyVim extras (mini.files) + version state
├── .neoconf.json             # lua_ls / neodev types for editing this config
├── stylua.toml               # StyLua style for the config's own Lua (2-space, 120 col)
├── after/
│   └── queries/               # Tree-sitter query extensions (see lua/plugins/asm.lua)
│       ├── asm/injections.scm # inject C into .S/.s cpp directive lines
│       ├── c/injections.scm   # inject asm into inline asm("…") bodies
│       └── cpp/injections.scm # same, for kernel headers detected as cpp
├── colors/
│   └── spaceduck.lua         # hand-written "spaceduck" colorscheme (+ lualine theme)
└── lua/
    ├── chkeys.lua            # on-screen keystroke display (ChKeys)
    ├── dbg/                  # debugger panels and target discovery
    │   ├── discover.lua      # reads /proc to find running QEMU gdbstubs, ELF arch, KASLR evidence
    │   ├── context.lua       # classify the session linux_kernel | native | managed (managed keeps stock dap-view)
    │   ├── qemuser.lua       # spawn/stop a usermode qemu-<arch> gdbstub for cross-arch userspace debugging
    │   ├── kernel.lua        # target picker + evidence report, builds the dap configuration
    │   ├── caps.lua          # asks the target which symbols/commands/registers actually exist
    │   ├── gdbq.lua          # runs a gdb command through the DAP repl, strips ANSI
    │   ├── safemem.lua       # classifies an address as RAM / device / unmapped before reading it
    │   ├── memory.lua        # configurable hex view (target, physical, or a file on disk)
    │   ├── registers.lua     # register panel with symbol annotation and change marks
    │   ├── mappings.lua      # parsed memory map
    │   ├── session.lua       # target panel, detach-safe stop, robust continue
    │   ├── layout.lua        # compact (tabs) vs wide (side panel) window layouts
    │   ├── panel.lua         # scratch buffer / window plumbing
    │   └── ui.lua            # panel highlights, section banners, window styling
    ├── config/
    │   ├── lazy.lua          # lazy.nvim + LazyVim bootstrap
    │   ├── options.lua       # editor options (tags, guicursor, no swap/modeline) + .S/.s/.lds/.lds.S filetypes
    │   ├── keymaps.lua       # ChKeys setup + <leader>uK toggle
    │   └── autocmds.lua      # C/C++ 4-space indent, cscope auto-load, tagfunc reset
    ├── lsp_filter/           # custom per-path LSP gating module
    │   ├── init.lua          # public API, LspAttach gating, registry persistence
    │   ├── rules.lua         # rule engine (within/contains → disable/diagnostics_off)
    │   └── util.lua          # path / JSON helpers (atomic writes)
    └── plugins/
        ├── dap.lua           # nvim-dap + dap-view + disassembly, adapters, keymaps, commands
        ├── clangd.lua        # clangd cmd + dynamic -j, inlay hints off
        ├── cscope.lua        # cscope_maps.nvim + Telescope, <leader>i* navigation
        ├── asm.lua           # asm/linkerscript parsers + at-line-start? cpp-injection predicate
        ├── diagnostics.lua   # CursorHold auto floating diagnostics
        ├── elixir.lua        # elixir/heex/eex Tree-sitter parsers (Neovim ships no regex syntax for them)
        ├── formatting.lua    # oxfmt as the conform formatter for web filetypes; its LSP mode stays off
        ├── fs_refresh.lua    # external change auto-reload + :FsRefresh
        ├── lsp_filter.lua    # wires up lsp_filter + <leader>cF* keys
        ├── mason.lua         # Mason packages this config expects (ensure_installed)
        ├── im_control.lua    # Korean langmap + IME auto-reset
        ├── imstate.lua       # Caps Lock + fcitx5 lualine indicators
        ├── lualine.lua       # full path + encoding/format flag
        ├── git_tag.lua       # git describe tag beside the branch
        ├── mini-files.lua    # <CR> = open file & close / enter dir
        ├── snacks.lua        # bigfile 5 MiB, picker shows hidden + ignored
        ├── colorscheme.lua   # selects spaceduck (+ alternate schemes installed)
        ├── markview.lua      # markdown rendering (markview.nvim)
        ├── neovide.lua       # Neovide GUI settings + zoom/paste keys
        └── example.lua       # disabled LazyVim template (inert: `if true then return {} end`)
```

---

## Features in detail

### Bootstrap & base (`init.lua`, `lua/config/lazy.lua`)

`init.lua` does nothing but `require("config.lazy")`. `lazy.lua` clones lazy.nvim's stable branch into `~/.local/share/nvim/lazy/lazy.nvim` on first run, imports the LazyVim distribution plus this repo's `lua/plugins/`, and tweaks a few defaults:

- `defaults.lazy = false` — plugins load eagerly at startup (predictable over fast).
- `defaults.version = false` — track latest commits rather than tagged releases.
- `install.colorscheme = { "gruvbox-material", "tokyonight", "noctis" }` — the post-install fallback list (the active scheme is set separately to `spaceduck`).
- `checker.enabled = true`, `checker.notify = false` — silent background update checks.
- Built-in plugins `gzip`, `tarPlugin`, `tohtml`, `tutor`, `zipPlugin` are disabled.

### Editor options (`lua/config/options.lua`)

Layered on top of LazyVim's defaults:

- `tags = "./tags;,tags;"` — search a `tags` file beside the current file and upward through parent directories (suits a kernel tree where `tags` sits at the repo root).
- `guicursor` — block cursor in normal/visual/command, a thin bar in insert, with blink timing (mainly visible in GUIs/Neovide).
- `modeline = false`, `swapfile = false` — no in-file modelines, no `.swp` files (note: no swap-based crash recovery).
- `whichwrap` extended so `h`, `l`, and the arrow keys wrap across line boundaries.
- `vim.filetype.add` — `.S`/`.s`/`.sx` are pinned to `asm` (GNU as) so files that define `.macro` are not misdetected as `vmasm`; `.lds` maps to `ld` (bare linker scripts), and a `*.lds.S` filename pattern maps cpp-preprocessed kernel linker scripts (e.g. `vmlinux.lds.S`) to `ld` too (see below).

### Linux kernel C workflow (`lua/config/autocmds.lua`, `lua/plugins/clangd.lua`, `lua/plugins/cscope.lua`)

- **Indentation** — `c`/`cpp` buffers default to 4 spaces (`tabstop = shiftwidth = softtabstop = 4`, `expandtab`). A `.clang-format` found upward from the file overrides that width (`IndentWidth`, `UseTab`, `TabWidth`, or the `BasedOnStyle` default), and a project `.editorconfig` takes precedence over both. This does not depend on clangd, so it holds where `lsp_filter` has turned the server off. `list = true` and `vim.b.autoformat = false` (no clang-format-on-save) apply in every case.
- **clangd** is launched as `clangd --background-index --clang-tidy --completion-style=detailed --header-insertion=never -j=<N>`, where `<N>` is **half the logical CPUs** (at least 1, so it's host-dependent). `--header-insertion=never` avoids auto-inserting `#include`s, which matters for kernel code. Inlay hints are disabled.
- **cscope** — `cscope_maps.nvim` (with a Telescope picker) provides navigation under the `<leader>i` prefix; its own default mappings and tag keymap are disabled so only the explicit bindings apply. On reading a `*.c`/`*.h`/`*.S` file, the nearest `cscope.out` found upward is auto-added once per session.
- **`<C-]>` → tags, not LSP** — on `LspAttach` to `c`/`cpp`/`h` buffers the LSP `tagfunc` is cleared, so `<C-]>` jumps through the `tags` file (ctags) instead of LSP go-to-definition. This is a deliberate override; generate a `tags` file (`make tags`) to use it.

### Low-level / cpp-preprocessed highlighting (`lua/plugins/asm.lua`, `after/queries/{asm,c,cpp}/injections.scm`)

Kernel low-level sources mix several languages in one file, and the stock grammars leave the embedded parts flat. This config injects the right grammar into each embedded region and pins the filetypes so the parsers actually run:

- **cpp in assembly** — `.S`/`.s` are run through the C preprocessor by `as`, so they are full of `#define`/`#include`/`#ifdef` and macro-based pseudo-instructions. The `asm` grammar treats every `#`-line as a plain comment (`#` is a GAS line-comment char), so `after/queries/asm/injections.scm` (`; extends` the bundled `asm` injections) injects the **C** grammar into `#` directive lines: `#define`/`#include`/`#ifdef`/`#endif` become keywords, macro names `@constant.macro`, include paths strings, `CONFIG_*` operands constants. The rest of the line (an assembly macro body) stays assembly.
- **`#at-line-start?` predicate** (registered in `asm.lua`) — restricts that injection to `#` directives that lead a line (only whitespace before `#`). Without it, a trailing `mov x0, x1  # else branch` comment — which the `asm` grammar sometimes parses as a comment node — would be mis-highlighted as C. Deleting this predicate breaks the query (unknown predicate), so the two files travel together.
- **assembly in C/C++** — `after/queries/c/injections.scm` and `.../cpp/injections.scm` inject the **asm** grammar into inline `asm("…")` / `__asm__(…)` bodies (`gnu_asm_expression`), so mnemonics, `%0` operands and `#imm` immediates in kernel inline assembly are highlighted instead of being one flat string. Each string piece is injected independently so multi-line and adjacent-literal (`"…\n\t" "…\n\t"`) blocks read cleanly. `cpp` is included because Neovim detects kernel `*.h` headers as `cpp`.
- **filetype pinning** — `.S`/`.s`/`.sx` are forced to `asm` in `options.lua` (Neovim otherwise flips files containing `.macro`/`.title`/… to `vmasm`, which has no Tree-sitter parser); `.lds` maps to `ld`, and a `*.lds.S` filename pattern maps cpp-preprocessed kernel linker-script templates to `ld` too.
- **parsers** — `asm`, `c`, `cpp`, `linkerscript`, and `devicetree` are added to `ensure_installed`.
- **linker scripts** — bare `*.lds`/`*.ld` and cpp-preprocessed `*.lds.S` (e.g. `vmlinux.lds.S`) both use the `linkerscript` grammar (`SECTIONS`/`ENTRY`/`MEMORY`/`ALIGN`/`KEEP`/output-section descriptions). `*.lds.S` needs a filename pattern because its `.S` extension would otherwise pin it to `asm`. Trade-off: the `linkerscript` grammar has no `#` handling, so cpp directive lines (`#include`/`#ifdef`/`#define`) parse as `ERROR` nodes and lose highlighting — this is accepted because the linker-script structure (the reason the file is read) is then highlighted correctly, whereas the `asm` fallback mis-tokenises `SECTIONS`/`ALIGN`/output sections as assembly (measured ~12% vs ~18% parse-error nodes on a real `vmlinux.lds.S`).
- **device trees** — `*.dts`/`*.dtsi` use the `devicetree` grammar, which handles cpp `#include`/`#define` natively (no injection needed) and does not confuse them with `#address-cells`-style properties.

Known ceiling: this is injection, not preprocessing, so `#if 0 … #endif` bodies are still highlighted (Tree-sitter cannot evaluate the preprocessor), and an assembler directive used as a `#define` body (`#define __HEAD .section …`) is tokenised by the C grammar rather than the assembly grammar.

### Debugging (`lua/plugins/dap.lua`, `lua/dbg/`)

The debug adapter is GDB itself. GDB 14 and later ship a Debug Adapter Protocol interpreter (`gdb -i dap`), so `nvim-dap` talks to the same GDB that already loads your `~/.gdbinit`, pwndbg and any Python tooling you source there. Nothing is proxied through GDB/MI, and no VS Code adapter has to be installed.

**Which languages are wired up.** C, C++ and assembly go through GDB. Rust offers all three of `codelldb` (renders `Vec`/`String`/`Option` properly), `lldb-dap` and `gdb` (which brings the registers, hex view, mappings and pwndbg with it) — the trade-off is written into each entry's name so the choice is visible at the point of choosing. JavaScript and TypeScript launch or attach through `js-debug-adapter`, picking up `tsx`/`ts-node`/`bun`/`deno` for a `.ts` file when one is on PATH. Python needs `debugpy`. Adapters are resolved from Mason's package directory rather than `PATH`, because Mason only extends `PATH` once it has loaded. Julia is not offered: the debugger shipped with `julia-lsp` expects three named pipes and a VS Code handshake, which is not the standard DAP launch model.

**The panels follow the session's context, decided from the adapter, not hardcoded per language.** A GDB session — the Linux Kernel adapter, or native C/C++/asm — gets the full panel set below. Every other adapter (Python, Rust through `codelldb`/`lldb`, JavaScript/TypeScript, and the rest) keeps `nvim-dap-view`'s own views — Scopes, Watches, Call stack, Breakpoints, Exceptions, the REPL and Output — and none of the GDB/kernel panels attach: the stop hooks, the layout takeover and the winbar's GDB-only sections stay out of a session that has no use for them, and asking for a GDB-only view (Registers, Memory, Mappings, disassembly, the control-flow graph) is refused with a note. Within a GDB session the low-level panels still degrade rather than break — `:DbgState` reports which of them the target actually supports and why.

**Running a program.** The launch configurations ask for the executable and then for its command line; the arguments are split with shell quoting rules and handed to the program as `argv`, so `hello world` is two arguments and `"hello world"` is one. Both prompts remember what you last answered. The answers GDB actually ran with are kept, so a later `<leader>dc` with no session replays them without asking again and goes straight to your breakpoints — `<leader>dn` is how you pick a different configuration or a different program.

**Adapters.** `gdb` for C/C++ (launch, launch-and-stop-at-main, attach by PID, and two cross-architecture usermode entries described below), `lldb` (`lldb-dap`) for Rust because it renders enums and `Vec`/`String` correctly, and `gdb_kernel` for remote targets. The kernel adapter is a function: it picks `<triple>-gdb` for the target architecture when one exists, adds `add-auto-load-safe-path <kernel root>` so the tree's `vmlinux-gdb.py` (`lx-*` commands) loads, sources gdbtools (`gdbtools.py`) when it is found — from `$GDBTOOLS_PATH`, by walking up from the kernel root, or from the checkout path gdbtools' own `setup.sh` recorded — and passes the full environment through (libuv replaces the environment rather than merging it, so `HOME` — and therefore `~/.gdbinit` — is lost if you don't).

**A foreign-architecture userspace binary runs under a usermode QEMU, and the toolchain follows from the ELF.** The two entries the *Adapters* line names sit under C, C++ and asm. *Run on QEMU user* asks for the guest binary, its arguments and a gdbstub port, starts `qemu-<arch> -g <port> -L <sysroot> <binary>` in the background and attaches; QEMU holds the guest at its entry until gdb connects, so the session opens stopped at `_start`. *Attach to a QEMU user gdbstub* connects to one you started yourself — `qemu-aarch64 -g 1234 -L /usr/aarch64-linux-gnu ./a.out` — and reads the binary only for symbols. Nothing is named twice: the architecture is the ELF's `e_machine`, and the cross gdb (`aarch64-linux-gnu-gdb`, `riscv64-linux-gnu-gdb`, or a multiarch `gdb`), the `set sysroot` and, for a launch, the `qemu-<arch>` itself all follow from it. x86_64, aarch64 and riscv64 are wired; the sysroot is the host cross-toolchain's `/usr/<triple>`, probed and left unset for a static binary. A QEMU this editor launched is stopped by its port alone — never a blanket kill — when the session ends or Neovim exits, while a stub you started is left running. The session is `native`, so it gets the same panels, control-flow graph and gdbtools commands as a host-native program.

**Attaching to a kernel has two ways in, offered together.** After picking the target, `<leader>dq` asks how: attach where the kernel has already got to, or arm the early-boot machinery and stop on the very first `head.S` instruction with the MMU still off. The second runs `kearly on`, then `kearly bootbreak` to walk past the reset vector to the kernel entry and calibrate the phys/virt offset, then `kearly status`, and stops there: `_text`, physical addresses, ready to be stepped one instruction at a time through the MMU enable and the branch into the high map. `kearly kaslr auto` is deliberately not run, because it advances to that branch and leaves the first step landing in virtual addresses; type it in the gdb console when you want to stop at the crossing itself. A breakpoint set while the slide is still unknown arms a catcher on the crossing by itself, so symbols line up without it. Nothing can be calibrated before `bootbreak`, and the slide cannot be recovered before the calibration exists. The KASLR state comes from the guest's own `-append` line or the build's `CONFIG_RANDOMIZE_BASE`, and on x86 the recovery also needs `GDBTOOLS_X86_KASLR` in the adapter's environment, which a console command cannot set. A target with no `kearly` is told so rather than sent commands it does not have.

**A gdbstub that dies takes the session with it, and now says so.** Requests to a dead stub are simply never answered, so the QEMU process the target was discovered from is watched while the session runs; when it disappears the session is closed with the reason and the debug windows go with it.

**Finding a target.** `<leader>dq` lists the QEMU instances currently exposing a gdbstub. Nothing is hardcoded: every candidate is built by reading `/proc/<pid>/cmdline` of each `qemu-system-*` process and parsing its actual `-gdb`, `-S`, `-kernel`, `-append`, `-M` and `-cpu` flags; the symbol file is derived from the `-kernel` path (stripping `arch/*/boot/*`, or using the image itself when it is an ELF, as for bare-metal targets); the architecture comes from the symbol file's ELF `e_machine`; the port is confirmed against `/proc/net/tcp`, never by dialling it, because a QEMU gdbstub accepts a single client and an exploratory connection disturbs it. KASLR is reported from the guest's own `-append` line, falling back to `CONFIG_RANDOMIZE_BASE` in the build's `.config`. `<leader>dQ` shows the same data as a table with the evidence for every field, and anything without evidence is reported as unknown rather than guessed.

**Panels** (`nvim-dap-view`, one bottom window with a winbar): Scopes, Locals+Globals, Watches, Registers, Memory, Mappings, Disassembly, Call stack, Breakpoints, Target, gdb console and Output. The console is `nvim-dap`'s REPL wired to GDB's own command interpreter, so `bt`, `vmmap`, `telescope`, `context`, `checksec`, `kearly`, `lx-dmesg` and everything else your GDB and pwndbg know can be typed there; `baleia.nvim` colorizes the ANSI those commands emit.

It takes input the way a console does. `<CR>` in normal mode sends the line under the cursor to GDB rather than triggering nvim-dap's variable expansion, and pressing it on an earlier `dap>` line runs that command again, so the scrollback doubles as history. `i`, `a`, `A` and `I` jump to the prompt from anywhere in the buffer. Expansion is still what `<CR>` does on a result line. The console buffer outlives the session, so the output is still there to read after the program exits.

There is no completion popup. blink.cmp makes an explicit exception for `dap-repl` buffers and completes them from buffer words, which in a console means suggestions scraped out of your own backtrace, over a menu tall enough to bury the prompt. It is switched off there. GDB's own completion is still one `<C-x><C-o>` away, because nvim-dap points the buffer's omnifunc at the DAP `completions` request, and it knows every command your GDB and pwndbg define.

**Execution control typed into the console goes through nvim-dap.** `c`, `n`, `s`, `ni`, `si`, `finish`, `q` and `kill` are answered by the client rather than passed to GDB, and the console echoes what happened. Sending them straight to GDB does work once and then breaks: the panels keep showing a target that is no longer stopped, and the frame ids GDB handed out go stale, so the next command dies with `list index out of range`. Everything that only inspects state — `bt`, `info`, `p`, `x`, `vmmap`, `telescope`, `context` — is passed through untouched.

- **Registers** merges the DAP register scope with one `info symbol` sweep over the general-purpose set, so values that point at something show `<symbol+offset>`. Registers that changed since the previous stop are marked. System and vector registers are collapsed into a compact grid below (an arm64 target exposes about 430 of them). `f` filters by name, `<CR>` opens the value under the cursor in the hex view.
- **Memory** is a hex view whose source and layout are yours to pick (`t` and `L`, or `:DbgMemory`). Sources: any expression or address, a physical address (read through the QEMU monitor), or a file on disk. Layout: bytes per row (or fit-to-window), bytes per group with a byte-order toggle, row count, ASCII column, and symbol annotation for 8-byte groups. Targets can be pinned and switched. Only the presets that the target actually supports are offered.
- **Mappings** parses `vmmap` into a table; `<CR>` opens a region in the hex view.
- **Locals+Globals** puts what the frame owns on the left and what the file owns on the right. DAP only publishes the scopes the adapter chooses — GDB publishes Arguments, Locals and Registers — so the file-scope side is collected separately, from the symbols the current compilation unit declares, `static` included. A name that cannot be read here is not listed: a variable whose block has ended simply leaves, and the count in the header says so. The one exception is a variable the compiler threw away, which keeps its row and is tagged `opt`, because there the name is real and only the value is missing.
- **Values appear where variables are used, not only where they are declared.** dap-view annotates the treesitter definition captures, which is the declaration line; a macro argument list is all uses and stays bare. The same values — no extra round trip — are also placed at the end of every visible line that mentions them. End of line, not inline: inline text pushes the code sideways and turns `type->cnt` into `type` and a distant `->cnt`. `:DbgInline off` turns it off.
- **Target** shows the session, and queries the target for whatever is applicable — `lx-version`, `kearly` and `mmview` for a kernel, `checksec` and `piebase` for a userspace process.

**The disassembly marks where the program counter is and where a branch is about to go.** The current instruction is marked by background alone, taken from the theme's own diff colour, so the instruction keeps its syntax colours instead of competing with a text marker. When the program counter is standing on a branch that will be taken, a connector is drawn from it to its destination; a branch that will fall through draws nothing, because the absence is the answer. When the condition cannot be decided the connector is dim, so an unknown is never mistaken for a certainty.

Whether a branch will be taken is worked out per architecture, from the registers the target actually exposes rather than from a configured architecture name: `cpsr` flags for aarch64 `b.<cond>`/`cbz`/`cbnz`/`tbz`/`tbnz`, `eflags` for the x86 `jcc` family, and a direct register comparison for riscv `beq`/`bne`/`blt`/`bge`/`bltu`/`bgeu`. An indirect branch has no address in the text, but standing on it the register that decides where it goes is already known, so `ret`, `br`, `blr`, `jr`, `jalr` and `jmp *%rax` resolve their destination from the stopped state. Everything is computed on fixed-width hex strings, not doubles: `0xffff8000803a1870` loses its top nibble as a double, and an address that is wrong by a nibble is worse than no address at all. The connector cannot live in the sign column — dap-view sets `statuscolumn = ""` on its panel — so it is drawn as an equal-width prefix on every row, which keeps the listing aligned.

**A build without `-g` is as usable as it is in plain gdb.** GDB answers `setFunctionBreakpoints` and `setInstructionBreakpoints`, which need no line table, but nvim-dap has no API for either, so the list is kept here and pushed to the session before it starts running. `<leader>dF` breaks on a symbol or a `0x` address, which is what `break main` does, and it works whether or not a session is up. `<leader>dg` opens every breakpoint the debugger will stop on — line, function and address — in a picker.

Two things follow from having no line table, and both match what plain gdb does rather than being worked around: a breakpoint on the function you are already stopped in sits behind the program counter and never fires again, and `list` in a frame with no debug info falls back to whatever source gdb has loaded. Stepping does adapt: with no line table `<leader>dO` and `<leader>di` switch to instruction granularity and say so once, instead of asking gdb to step over a line that does not exist.

**The frame you are on is the frame gdb is on.** nvim-dap selects the first frame that carries a source so it has somewhere to jump; on a binary without debug info that silently selects the caller, which is how the marker, the status line, `list` and even the `rip` in the register panel ended up describing a glibc header while `bt` said `main`. The selection is put back on frame 0 before anything reads it, so the registers, the scopes and the console all describe the same frame.

When that frame has no source there is no line to point at, so the stale marker is removed rather than left claiming a line the program is not on, and the panel switches to the disassembly, which is the only view that can follow the program counter without a line table. The console is left alone if that is what you are looking at — you are typing in it, and the location is echoed there anyway, the way gdb prints it.

**What the session supports is decided up front, not discovered by failing.** `:DbgState` reports the case it detected — adapter, launch or attach, kernel/userspace/bare metal, and whether the program carries embedded DWARF, a separate debug file or none — and then answers yes or no for line breakpoints, source stepping, function breakpoints, instruction breakpoints, disassembly and the QEMU monitor, with the reason attached to every no. Features that are unavailable are refused with that reason instead of being attempted and failing somewhere deeper.

**What the target can do is measured, not assumed.** On each attach, GDB is asked which of a set of symbols resolve, which commands exist, which registers the architecture has, and whether the QEMU monitor answers. A kernel is recognised by `init_task`/`linux_banner`/`swapper_pg_dir` resolving, userspace by `__libc_start_main`/`environ`/`main_arena`, anything else is treated as bare metal. Menu entries that make no sense for the current target — a heap pointer on a kernel, kernel symbols on a bare-metal image — are simply absent.

**Memory reads are guarded.** A debug read of a guest address that translates outside RAM makes QEMU dispatch into a device model, and that path has been observed to take the VM down with the debug session. Before reading, the address is checked with `monitor gva2gpa` and `monitor gpa2hva`. `gva2gpa` answers for whichever core QEMU's monitor is currently pointed at, which is state shared with everything else on that gdbstub, so the monitor is aimed at the core the session is stopped on before the question is asked rather than inheriting wherever it was left. RAM is read normally, an address that is not a live virtual address but is physical RAM is read through `monitor xp`, and a device region or a hole is refused with the reason shown. `o` reads anyway, `:DbgSafeMem off` disables the guard, and it is inert for adapters with no QEMU monitor behind them.

**Stopping a session detaches rather than kills.** GDB's DAP maps `terminate` to `kill`, which ends the QEMU guest; `<leader>dt` therefore issues a disconnect without terminating for attach sessions and only kills for launched processes. `<leader>dT` is the explicit kill.

**Layout follows the terminal, not the monitor.** The only measurement used is the cell grid Neovim reports as `columns` and `lines`, so changing the font size with `ctrl-+` / `ctrl--` in the terminal counts as a resolution change and the layout is re-measured on the spot. Below the threshold everything lives in the bottom panel's tabs and the winbar labels shorten; above it a side column appears beside the source and carries one panel at full height, with the bottom bar running the whole width underneath both.

| Terminal | Mode | Side column | Panels stacked | Source width |
|---|---|---|---|---|
| 120x32 | compact | — | 0 | 120 |
| 140x36 | wide | 42 | 1 | 98 |
| 200x50 | wide | 60 | 1 | 140 |
| 240x60 | wide | 72 | 1 | 168 |
| 280x70 | wide | 78 | 2 | 202 |
| 320x90 | wide | 78 | 3 | 242 |

A second panel only appears once the first still gets every row it needs — a register panel is worth little cut off halfway through the general set — so a 50-line terminal keeps the column for Registers alone and stacks nothing under it.

A wide terminal gets the column, a narrow one gets none: both dimensions are checked. The column holds a single panel, Registers by default, because that is the one you read continuously and it is worth the full height; everything else is one keystroke away in the bottom bar. dap-view resizes its own window whenever another appears, which reflows the column, so the sizes are re-applied on every stop and whenever a window opens or closes. `]p`/`[p` rotate which panels the column shows, skipping any that another window already has. `:DbgLayout auto|wide|compact` overrides the mode and reports the measurement it settled on.

**Source always opens in a source window.** nvim-dap's fallback is "the window you were in before", which is a debugger panel when you step from the console, and dap-view pins its panel with `winfixbuf`; the jump then fails with `E1513` from inside nvim-dap's coroutine and takes the step down with it. A `switchbuf` function picks a window holding an ordinary file instead, splitting one off if none exists, and does it without stealing focus from wherever you are typing.

**One window per panel, one handle per window.** Panel buffers and the windows the debugger owns are registered in a single place (`lua/dbg/panel.lua`) and handed out from there, with a `WinClosed` hook dropping a handle the moment its window goes away. No module keeps its own copy, so a closed window cannot be mistaken for a live one and two callers cannot each believe they hold the real thing.

**The debug windows come and go with the session.** Starting a session records the window layout first, then opens the panels; ending one closes everything the debugger opened and puts the layout, the focused window and its buffer back, so a session that walked into `libc_start_call_main.h` does not leave you there. The sources the debugger listed on its way through — that glibc header among them — are dropped from the buffer list too, unless you edited them or still have them open. `:DbgClose` does the same by hand. Each panel also lives in exactly one window at a time: ask for Registers somewhere new and the old window gives it up, the side panel moving on to the first panel nothing else is showing.

**The session says what it is doing.** Starting, exiting (with the exit code), detaching and stopping for an unexpected reason are all reported through `vim.notify`. So is a breakpoint that never bound, together with why — a breakpoint reported unverified while GDB has not loaded the program yet is normal and stays quiet, but one that is still unbound when the session ends is called out, and if the executable has no `.debug_*` sections the message says it was built without `-g` instead of leaving you guessing.

### `lsp_filter` — per-path LSP gating (`lua/lsp_filter/`, `lua/plugins/lsp_filter.lua`)

A small custom module that turns LSP servers **off for chosen files or directories** — handy for excluding generated/third-party files in a large tree from clangd noise.

- Two actions: **`disable`** (detach the LSP client for that buffer) or **`diagnostics_off`** (keep the server, hide its diagnostics).
- Rules match by **`within`** (path prefix) or **`contains`** (a path segment / directory name anywhere in the path), scoped to specific servers (default `clangd`, `"*"` for all, or a custom list of server names via the advanced add).
- Rules persist as JSON at **`~/.local/share/nvim/lsp_filter/rules.json`** (under `stdpath("data")`, *not* inside the repo). Writes are atomic (temp file + fsync + rename) and refuse to clobber a symlink or non-regular file; a malformed registry aborts the write rather than risk data loss.
- Edit the registry with `<leader>cFe` — saving it reloads the rules automatically, so you rarely need `<leader>cFr` by hand.
- Optional per-project marker files (`.nvim-lsp-filter.json`, searched upward) are supported but **off by default**.
- The session toggle (`<leader>cFt`) is in-memory only and resets to enabled on restart.

#### Recipe — turn clangd off for a directory (no git footprint)

This is the main reason `lsp_filter` exists: silence clangd over a noisy subtree (generated code, a vendored copy, a giant driver dir) **without putting anything into any git repository** and while keeping it trivially reversible.

1. Open any file inside the directory you want to silence.
2. Press **`<leader>cFd`** and pick the directory (or an ancestor) from the list — or `<leader>cFf` for just the current file, or `<leader>cFa` to type a path and choose the server scope (`clangd` / all / a custom list) and action (`disable` / `diagnostics_off`).
3. The rule is written to **`~/.local/share/nvim/lsp_filter/rules.json`**. That path is Neovim's *data* directory (`stdpath("data")`) — it lives **outside every project and outside this config repo**, so neither the kernel tree's git nor this repo's git ever sees it. Nothing to `.gitignore`, nothing to accidentally commit.
4. From then on, whenever clangd tries to attach to a buffer under that directory, `lsp_filter` detaches it (`disable`). The rule **persists across restarts** because it is on disk.

Turning it back on:

| Want to… | Do this |
|----------|---------|
| Toggle the whole filter off for right now | `<leader>cFt` (session only; re-enabled next launch) |
| Remove a specific rule permanently | `<leader>cFe` → delete the line → `:w` (it reloads on save) |
| Re-read the registry after editing it elsewhere | `<leader>cFr` |
| See which rule (if any) is gating the current buffer | `<leader>cFl` |

> **Alternative — a project-local marker file.** `lsp_filter` can also honor a `.nvim-lsp-filter.json` placed in the project (searched upward), but marker support is **off by default**; enable it with `setup({ markers_enabled = true })` in `lua/plugins/lsp_filter.lua`. Since a marker file lives inside the project tree, exclude it from that project's git via `.git/info/exclude` (local, never committed) or your global gitignore. The registry approach above needs none of this, which is why it's the recommended one.

### Korean input-method integration (`lua/plugins/im_control.lua`, `lua/plugins/imstate.lua`)

- **`langmap`** maps Dubeolsik (2-set) Hangul jamo to their QWERTY keys, so Normal-mode commands keep working even when the OS IME emits Hangul.
- **Auto-reset** — on `InsertLeave` and `FocusGained` the IME is forced back to English/ASCII. The backend is detected at startup: `fcitx5-remote -c` (Linux), `im-select.exe` (Windows), or `issw` (macOS). If none is found, only the `langmap` applies. It resets *to* English; it never switches you *into* Korean.
- **Statusline indicators** — a single 200 ms libuv timer polls the Caps Lock LED (`/sys/class/leds/input*::capslock/brightness`) and the current fcitx5 input method (`fcitx5-remote -n`, run asynchronously), exposing `vim.g.caps_state` and `vim.g.im_state`. Each indicator is added to lualine only when its backend exists: a Caps Lock component (`󰬈 CAPS`, needs the LED node) and an input-method component (`한` for Hangul, otherwise `EN`/`en` — the case mirroring Caps Lock state, needs `fcitx5-remote`). On systems with neither `fcitx5-remote` nor a Caps LED node, this file contributes nothing.

### UI & appearance

- **`spaceduck` colorscheme** (`colors/spaceduck.lua`) — a complete hand-written theme with very broad Treesitter coverage and a dedicated C/C++ palette (macros, preprocessor directives, type qualifiers). Background is **transparent in the terminal** and **opaque under Neovide**; requires a true-color terminal. It also defines a matching lualine theme in `vim.g.spaceduck_lualine`, although the current `lualine.lua` does not wire it up (the statusline keeps LazyVim's default `auto` theme). `colorscheme.lua` selects spaceduck as the active scheme and installs `lush.nvim` / `noctis.nvim` / `gruvbox-material` as alternates.
- **lualine** (`lualine.lua`) — shows the **full path** (never truncated) and prepends an encoding/line-ending flag (e.g. `UTF-8/LF`, `UTF-8+BOM/CRLF`) to the right-hand section.
- **Git tag** (`git_tag.lua`) — right after the branch name, shows the tag that `git describe --tags` resolves to for the buffer's repository: `v6.12.95` when HEAD sits on the tag, `v6.12.95+12` when it is 12 commits past it. Repositories without tags, and buffers outside a work tree, show nothing. The lookup runs asynchronously per repository root and is cached for 10 s, so a redraw never spawns `git`. Since kernel trees tag releases as `v<version>`, this reads as the version of the tree you are in — including on a detached HEAD, where the branch component only shows a hash.
- **mini.files** (`mini-files.lua`, enabled via the LazyVim `editor.mini-files` extra) — `<CR>` opens a file and closes the explorer, or enters a directory. The open mappings (`<leader>fm` / `<leader>fM`) come from the LazyVim extra.
- **Snacks** (`snacks.lua`) — `bigfile` enabled at a **5 MiB** threshold; the explorer/files/grep picker sources show **hidden *and* gitignored** files. (In a kernel tree this surfaces a lot of build artifacts — expect noisier pickers.) The explorer's filesystem watcher (`watch`) is pinned on so the tree keeps following external changes even if the upstream default flips.
- **markview** (`markview.lua`) — `markview.nvim` for in-buffer Markdown rendering, loaded eagerly with default settings (needs a Nerd Font).
- **Diagnostics** (`diagnostics.lua`) — line diagnostics pop up automatically in a rounded, non-focusable float on `CursorHold` (after the `updatetime` delay), with the source always shown, and close when you move to another line, enter insert mode, or hide the buffer.

### External change detection & refresh (`lua/plugins/fs_refresh.lua`)

Out of the box, LazyVim only runs `:checktime` on `FocusGained`/`TermClose`/`TermLeave`, so files rewritten by another program (an AI coding agent, `git` in another terminal, a build) while the editor keeps — or never regains — focus are not picked up. This module makes detection unconditional, in terminals and Neovide alike:

- **Buffers** — a 2 s libuv poll timer plus `BufEnter`/`CursorHold`/`CursorHoldI` autocmds run `:checktime`; unmodified buffers reload automatically (`autoread`), real conflicts still raise the usual W12 prompt. A notification reports what was reloaded (batched when many buffers reload at once).
- **snacks explorer** — already watches every expanded directory via libuv `fs_event` (see above); collapsed levels are only re-scanned on demand via `:FsRefresh`.
- **mini.files** — has no watcher of its own, so an open explorer is re-read on the same 2 s tick. The re-read is skipped while any mini.files buffer holds pending manual edits (a typed rename/create is never clobbered or prompted over).
- **`:FsRefresh`** / `<leader>uR` — explicit refresh: `checktime` over all buffers, a full re-scan of every open snacks explorer tree (including collapsed levels), and a mini.files re-read. If mini.files has pending edits, mini.files itself asks before discarding them.

### ChKeys — on-screen keystroke display (`lua/chkeys.lua`)

A self-contained keystroke caster for screencasts. It captures keys via `vim.on_key` and renders them in colored, rounded floating windows at the bottom-right, auto-dismissing after ~1.6 s. It auto-enables the **kitty keyboard protocol** on supported terminals (kitty, WezTerm, foot, ghostty, rio) for precise modifier detection, shows a `한` indicator when `vim.g.im_state == "한"`, and is purely in-memory (nothing is written to disk). Toggle with `<leader>uK` or `:ChKeysToggle`. Under Neovide it uses one window per key (`per_key_window`).

### Neovide GUI (`lua/plugins/neovide.lua`)

Everything here is guarded by `if vim.g.neovide` — it's inert in a terminal. It sets the GUI font to `CaskaydiaCove_Nerd_Font_Mono:h12:w-1`, a 120/5 Hz refresh rate, subtle cursor animation, full window padding, full opacity, a quit-confirmation prompt, and the zoom/paste keymaps below.

---

## Keymap reference

`<leader>` is **Space** (LazyVim default). These are the mappings this repo adds **on top of** the standard LazyVim keymaps.

### Kernel navigation — cscope (Normal mode, prefix `<leader>i`)

| Key | Action |
|-----|--------|
| `<leader>is` | Find this **s**ymbol |
| `<leader>ig` | Find this **g**lobal definition |
| `<leader>ic` | Find functions **c**alling this function (callers) |
| `<leader>id` | Find functions called by this function (callees) |
| `<leader>it` | Find this **t**ext string |
| `<leader>ie` | Find this **e**grep pattern |
| `<leader>if` | Find this **f**ile (filename under cursor) |
| `<leader>ii` | Find files **i**ncluding this file |
| `<leader>ia` | Find **a**ssignments to this symbol |

### Debugging (Normal mode, prefix `<leader>d`)

| Key | Action |
|-----|--------|
| `<leader>dc` | Run / continue — with no session, replays the last configuration without re-prompting |
| `<leader>dn` | Start a new session and choose the configuration, executable and arguments again |
| `<leader>db` / `<leader>dB` | Toggle breakpoint / conditional breakpoint |
| `<leader>dF` | Break on a function name or a `0x` address (works without `-g`) |
| `<leader>dg` | List every breakpoint — line, function and address — in a picker |
| `<leader>dC` | Run to cursor |
| `<leader>di` / `<leader>do` / `<leader>dO` | Step into / over (`next`) / out (`finish`) — instruction granularity when there is no line table |
| `<leader>dj` / `<leader>dk` | Move down / up the call stack |
| `<leader>dP` | Pause |
| `<leader>dt` | Stop — detaches when attached, terminates a launched process |
| `<leader>dT` | Terminate for real (kills a QEMU guest) |
| `<leader>dl` | Run last configuration |
| `<leader>du` | Toggle the debug panel |
| `<leader>de` / `<leader>dw` | Evaluate under cursor / add a watch (asks for the expression when the cursor is in a panel) |
| `<leader>dr` | Toggle the gdb console |
| `<leader>dR` / `<leader>dm` / `<leader>dM` / `<leader>dD` | Registers / hex view / mappings / disassembly |
| `<leader>ds` | Target panel |
| `<leader>dq` | Pick a QEMU gdbstub and attach |
| `<leader>dQ` | Report every debug target found on this host, with the evidence |
| `<leader>dv` / `<leader>dV` | Toggle the side panel / pick which panel to show |

Inside the hex view: `t` source, `L` layout, `g` go to, `w` bytes per row, `g`…`]]`/`[[` page, `<CR>` follow pointer, `p`/`x`/`s` pin/unpin/switch, `e` byte order, `A` ascii column, `N` symbol annotation, `W` width fitting, `a` auto refresh, `o` read past the guard, `r` refresh. Inside Registers: `f` filter, `r` refresh, `<CR>` open the value in the hex view. Inside Locals+Globals: `r` refresh, `f` name filter, `<CR>` pin the name to Watches, `K` ask `ksym` what the address on the line is — it answers for a physical address as readily as a virtual one, which is what makes it useful before the MMU is on. It stops at naming the address: whether a number is a pointer at all is not decidable from the number, and following a wrong one is the read that takes QEMU down, so `kpt`, `kpgd` and `ktel` do the walking in the console where you have said what the value is. Inside the side panel: `]p`/`[p` switch panel.

### LSP filter (Normal mode, prefix `<leader>cF`)

| Key | Action |
|-----|--------|
| `<leader>cFf` | Exclude the **current file** (disable clangd for it) |
| `<leader>cFd` | Exclude a path for the current buffer (pick the file itself or any ancestor directory) |
| `<leader>cFa` | **Advanced** add — prompt for path, server scope, and action |
| `<leader>cFl` | **List** the decided action/source for the current buffer |
| `<leader>cFe` | **Edit** the rules registry (`rules.json`) |
| `<leader>cFr` | **Reload** rules from disk |
| `<leader>cFt` | **Toggle** the filter for this session |

### Misc & UI

| Key | Mode | Action |
|-----|------|--------|
| `<leader>uK` | n | Toggle the ChKeys keystroke display |
| `<leader>uR` | n | Refresh buffers & file explorers from disk (`:FsRefresh`) |
| `<CR>` | n (in mini.files) | Open file (and close explorer) / enter directory |

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
| `:DbgKernel` / `:DbgKernelEarly` | `plugins/dap.lua` | Attach to a QEMU gdbstub for a Linux Kernel; the second exports `GDBTOOLS_AUTO=1` |
| `:DbgTargets` | `plugins/dap.lua` | Report the debug targets found on this host |
| `:DbgMemory [expr\|file]` | `plugins/dap.lua` | Open the hex view |
| `:DbgRegisters` / `:DbgMappings` | `plugins/dap.lua` | Open the register / mapping panels |
| `:DbgSafeMem on\|off\|auto` | `plugins/dap.lua` | Guard memory reads against QEMU device-region dispatch |
| `:DbgLayout auto\|wide\|compact` | `plugins/dap.lua` | Switch the debugger window layout |
| `:DbgBreak [name\|0xADDR]` | `plugins/dap.lua` | Break on a function or an address, no line table needed |
| `:DbgBreakpoints` | `plugins/dap.lua` | List every breakpoint in a picker |
| `:DbgState` | `plugins/dap.lua` | Report what this session supports, and why not when it does not |
| `:DbgClose` | `plugins/dap.lua` | Close every debugger window and restore the previous layout |
| `:DbgInline on\|off` | `plugins/dap.lua` | Show variable values where they are used, not only where they are declared |
| `:ChKeysToggle` | `chkeys.lua` | Toggle the keystroke display |
| `:FsRefresh` | `fs_refresh.lua` | Reload changed buffers + refresh snacks explorer / mini.files |
| `:Cscope` / `:Cs` | `cscope_maps.nvim` | The `<leader>i*` keys wrap `:Cscope find …`; `:Cs` is used to auto-add databases |

---

## Caveats

- **Background is transparent in the terminal.** The `spaceduck` theme leaves `Normal` background unset so your terminal/compositor shows through; it only paints an opaque background under Neovide.
- **`<C-]>` does not use LSP** in C/C++/H buffers — it falls back to the `tags` file by design. Generate `tags` (`make tags` / `ctags`) for it to work.
- **Pickers include ignored files.** `hidden`/`ignored` are on for the Snacks file/grep/explorer sources, so build outputs and dotfiles appear — convenient, but noisy in a kernel tree.
- **No swap files.** `swapfile = false` means there's no swap-based crash recovery.
- **Unmodified buffers reload silently every ~2 s** when their file changes on disk (`fs_refresh`). The reload is undoable (`'undoreload'`), and a notification names the reloaded file.
- **Autoformat is off for C/C++.** Intentional, so kernel sources aren't reformatted on save.
- **`lsp_filter` rules live outside the repo** at `~/.local/share/nvim/lsp_filter/rules.json`, so they are machine-local and not version-controlled.
- **A QEMU gdbstub takes one client.** While Neovim is attached, a separate `gdb`/pwndbg session cannot connect, and vice versa. The gdb console panel is the way to run those commands instead. Target discovery never opens a connection to probe, and refuses a stub that already has a client.
- **Quitting Neovim mid-session is safe.** nvim-dap installs no `VimLeavePre` handler, so `:qa!` with a session up used to leave `gdb -i dap` reparented to init: a launched program kept running, and a QEMU target kept its single gdbstub client slot occupied so nothing could attach again. Sessions are now shut down on the way out, detaching for attach sessions so the guest survives and terminating for launched ones so the debuggee does not.
- **The hex view shows one window at a time.** The header spells out the range and the file size (`crc32 0x0-0x200 of 0xc9a8`) because a page boundary looks exactly like the end of the file otherwise; `]]` and `[[` move through it.
- **`<leader>dt` detaches, it does not kill.** That is deliberate: GDB's DAP `terminate` request runs `kill`, which ends the guest. Use `<leader>dT` when you actually want the guest gone.
- **The memory read guard is on for QEMU targets.** Addresses that are neither RAM nor translatable are refused with the reason; `o` overrides once and `:DbgSafeMem off` disables it. Symbol annotation in the hex view is capped at the first 128 values per page, and the header says so when it applies.
- **Source-line breakpoints need `-g`; symbol breakpoints do not.** Without DWARF a breakpoint on a line stays pending forever and the program runs to completion, so `<leader>db` refuses with that reason and points at `<leader>dF`, which breaks on a symbol and works on a plain `gcc -o prog prog.c` build. Build with `-g -O0` when you want line stepping and locals (`-O0` also stops the optimizer from folding away the line you meant to stop on).
- **Ending a session closes the debug windows.** Panels you opened by hand during the session close too, and the pre-session layout is restored. Nothing outside the debugger is touched.
- **Early-boot Linux Kernel tooling is not armed by default.** `:DbgKernel` leaves gdbtools' `kearly` commands registered but inert; `:DbgKernelEarly` exports `GDBTOOLS_AUTO=1`. The armed mode installs stop hooks that resume the target and rewrite the symbol table on their own, which a DAP client does not expect, so prefer a terminal session for that phase.
- **`example.lua` is inert** (`if true then return {} end`) — it's the LazyVim onboarding template and configures nothing.

---

## Credits

- **[spaceduck](https://github.com/pineapplegiant/spaceduck)** by *pineapplegiant* — MIT License, "Copyright (c) 2020 pineapplegiant". `colors/spaceduck.lua` here is an independent Neovim/Lua re-implementation that reuses the original spaceduck color palette and theme name. The upstream theme is MIT-licensed and its author explicitly welcomes ports.
- Built on **[LazyVim](https://github.com/LazyVim/LazyVim)** and **[lazy.nvim](https://github.com/folke/lazy.nvim)** by *folke*.
- Notable third-party plugins: [cscope_maps.nvim](https://github.com/dhananjaylatkar/cscope_maps.nvim), [markview.nvim](https://github.com/OXY2DEV/markview.nvim), [mini.nvim](https://github.com/nvim-mini/mini.nvim), [snacks.nvim](https://github.com/folke/snacks.nvim), [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim), and [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).
