# nvim-config

A [LazyVim](https://www.lazyvim.org/)-based Neovim configuration tuned for **Linux kernel / C development**, with a GDB-native debugger, a per-path LSP gate, Korean input-method integration, an on-screen keystroke display, a hand-written colorscheme and a Neovide profile.

Linux is the primary target. The IME reset has Windows and macOS branches, but the kernel workflow, the Caps Lock indicator and the GUI font expect a Linux desktop.

---

## Highlights

- **LazyVim base.** [lazy.nvim](https://github.com/folke/lazy.nvim) manages plugins; LazyVim is the foundation and everything under `lua/plugins/` layers on top.
- **C/C++ indentation.** Buffers follow the tree's `.editorconfig` / `.clang-format`; without either, a tab-indented file gets 8-column tabs, anything else 4 spaces. Whitespace is shown and autoformat is off, so sources are never reflowed on save.
- **clangd, cscope and tags for big trees.** clangd runs with kernel-friendly flags and half the CPUs; cscope databases auto-load; `<C-]>` goes through the `tags` file instead of LSP.
- **Low-level highlighting.** `.S`/`.s` get the C grammar injected into `#` directive lines, C/C++ get the asm grammar inside `asm("…")`, and `.S`/`.s`, linker scripts and device trees are pinned to the right parsers.
- **Man pages read like source.** `:Man` buffers get the C grammar over their code blocks, headings and cross-references above roff's bold, and the same number/sign-column layout as any other buffer.
- **Debugger built on GDB's own DAP.** `nvim-dap` drives `gdb -i dap` (GDB 14+), so userspace C/C++, a foreign-architecture binary under a QEMU user-mode gdbstub, and a Linux kernel behind a QEMU gdbstub all work without a third-party adapter. Python, Rust, JavaScript/TypeScript and Elixir debug through their own ecosystems. GDB sessions get panels for registers, locals+globals, a hex view, memory mappings and target queries on top of `nvim-dap-view`.
- **`lsp_filter`.** Disable clangd (or any server) per file or directory through persisted rules.
- **Korean IME integration.** A Dubeolsik → QWERTY `langmap`, an IME reset to English on leaving Insert mode, and live fcitx5 / Caps Lock state in the statusline.
- **ChKeys.** A built-in keystroke caster for screencasts.
- **`spaceduck` colorscheme + Neovide profile.** Transparent in the terminal, opaque under Neovide.

---

## Requirements

| Group | Tool | Why |
|-------|------|-----|
| **Core (required)** | Neovim **0.10+** | `vim.uv`, `vim.fs.joinpath` and other recent APIs. |
| | `git` | Bootstraps lazy.nvim, clones plugins, feeds the statusline tag component. |
| | C compiler + `make` | Treesitter parsers are compiled locally. |
| | Network access | First launch fetches lazy.nvim and plugins. |
| **Search / UI (recommended)** | `ripgrep` (`rg`), `fd` | Backends for the Snacks picker / grep. |
| | A **Nerd Font** | Icons, statusline glyphs, the Caps Lock glyph, markview rendering. |
| **C / kernel workflow** | `clangd` | C/C++ language server. |
| | `cscope` | Symbol navigation; databases are auto-loaded. |
| | `universal-ctags` | Generates the `tags` file that `<C-]>` jumps through. |
| **Debugging (optional)** | `gdb` **14+** | The debug adapter is GDB itself (`gdb -i dap`). |
| | `codelldb`, `js-debug-adapter`, `debugpy`, `elixir-ls` | Installed through Mason. Rust, JavaScript/TypeScript, Python and Elixir debug on these. |
| | `qemu-system-*` | Kernel / bare-metal workflow; the gdbstub is what Neovim attaches to. |
| | `<triple>-gdb` (optional) | `aarch64-linux-gnu-gdb`, `riscv64-linux-gnu-gdb`, … preferred per target architecture; a multiarch `gdb` otherwise. |
| | `qemu-<arch>` usermode (optional) | `qemu-aarch64`, `qemu-riscv64`, … (package `qemu-user`) for the cross-arch usermode configs. |
| | `/usr/<triple>` cross runtime (optional) | Sysroot for a dynamically linked cross binary; auto-detected, unneeded for a static one. |
| **Korean IME (optional)** | `fcitx5` + `fcitx5-remote` | IME reset and the Hangul/English indicator. |
| **Caps Lock indicator (optional)** | Linux sysfs LED node | `/sys/class/leds/input*::capslock/brightness`. |
| **GUI (optional)** | [Neovide](https://neovide.dev/) | GUI front-end with a dedicated profile here. |
| | `CaskaydiaCove Nerd Font Mono` | The `guifont` Neovide uses. |
| | `wl-clipboard` or `xclip` | Backs the `+` register for the GUI paste mapping. |
| **Discord presence (optional)** | Discord desktop client | `discord_rpc.lua` talks to its IPC socket; Linux only, inert elsewhere. |
| **Editing the config (optional)** | `lua-language-server`, `stylua` | Lua completion/types and formatting for the config itself. |
| **Terminal (optional)** | kitty / WezTerm / foot / ghostty / rio | kitty keyboard protocol, for full ChKeys modifier capture. |

> For the kernel workflow, generate the index files from the source tree: `make C=2 compile_commands.json` (or `scripts/clang-tools/gen_compile_commands.py`), `make cscope`, `make tags`.

---

## Installation

Neovim reads its configuration from `$XDG_CONFIG_HOME/nvim` (`~/.config/nvim` by default). The last path component must be `nvim`; the methods below differ only in how that directory comes to point at this repository.

### 0. Back up any existing config

```zsh
mv ~/.config/nvim ~/.config/nvim.bak 2>/dev/null
# Optional: also stash the generated plugin/state/cache dirs for a clean slate
mv ~/.local/share/nvim ~/.local/share/nvim.bak 2>/dev/null
mv ~/.local/state/nvim ~/.local/state/nvim.bak 2>/dev/null
mv ~/.cache/nvim       ~/.cache/nvim.bak       2>/dev/null
```

### Method A — symbolic link (recommended; this is the current setup)

Keep the repository in your workspace and symlink it into place, so git operations happen there instead of under `~/.config`.

```zsh
git clone https://github.com/yugeun-song/nvim-config.git ~/workspace/nvim-config
ln -s ~/workspace/nvim-config ~/.config/nvim
```

### Method B — clone directly as the config directory

```zsh
git clone https://github.com/yugeun-song/nvim-config.git ~/.config/nvim
# add --depth=1 for a shallow clone if you don't need history
```

With a non-default `XDG_CONFIG_HOME`, clone into `"$XDG_CONFIG_HOME/nvim"` instead.

### Method C — clone elsewhere, then move or copy into place

```zsh
git clone https://github.com/yugeun-song/nvim-config.git /tmp/nvim-config
mv /tmp/nvim-config ~/.config/nvim        # relocate it, or…
cp -r /tmp/nvim-config ~/.config/nvim     # …keep a copy at the source too
```

`.git/` travels along, so `~/.config/nvim` remains a working clone.

### Optional — try it without touching your real config (`NVIM_APPNAME`)

`NVIM_APPNAME` makes Neovim read `~/.config/<name>` and use `~/.local/share/<name>` etc., leaving `~/.config/nvim` untouched:

```zsh
git clone https://github.com/yugeun-song/nvim-config.git ~/.config/test-nvim
NVIM_APPNAME=test-nvim nvim
```

### First launch

1. Run `nvim`. The first start clones lazy.nvim into `~/.local/share/nvim/lazy/` and installs every plugin.
2. Run `:Lazy` to watch the install, then `:LazyHealth` (or `:checkhealth`) to confirm external tools are detected.
3. Treesitter parsers compile on demand (a C compiler must be present).
4. Quit and reopen once so eager-loaded plugins and the `spaceduck` colorscheme settle.

### Updating

- **Plugins:** `:Lazy update`. Versions are pinned in `lazy-lock.json`. The config tracks the latest commit of each plugin (`defaults.version = false`) and checks for updates silently (`checker.enabled = true`, `checker.notify = false`).
- **Config:** `git -C ~/workspace/nvim-config pull` (Method A) or `git -C ~/.config/nvim pull` (Methods B/C).

### Mason packages

Mason installs into `~/.local/share/nvim/mason/`, outside this repository. `lua/plugins/mason.lua` lists the packages every machine needs in `ensure_installed`; LazyVim installs the missing ones on first launch.

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
│   ├── ftplugin/
│   │   └── man.lua            # man buffers: window options, then the man_code passes
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
    │   ├── breakpoints.lua   # function and address breakpoints, which nvim-dap has no API for
    │   ├── cfg.lua / cfgbox.lua # control-flow graph: gdbtools' cfgjson, drawn in a panel or in the source window
    │   ├── console.lua       # gdb console behaviour for the DAP repl, frame realignment
    │   ├── disasm.lua        # marks the instruction the program counter is on
    │   ├── inline.lua        # variable values at end of line, for a GDB session
    │   ├── notify.lua        # session messages and the log behind :DbgLog
    │   ├── watch.lua         # two-column locals/globals panel
    │   ├── watchdog.lua      # says so when the QEMU behind the session disappears
    │   ├── context.lua       # classify the session linux_kernel | native | managed (managed keeps stock dap-view)
    │   ├── qemuser.lua       # spawn/stop a usermode qemu-<arch> gdbstub for cross-arch userspace debugging
    │   ├── kernel.lua        # target picker + evidence report, builds the dap configuration
    │   ├── caps.lua          # asks the target which symbols/commands/registers actually exist
    │   ├── gdbq.lua          # runs a gdb command through the DAP repl, strips ANSI
    │   ├── qemumon.lua       # QEMU monitor passthrough: classifies an address as RAM / device / unmapped before reading it
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
    │   └── autocmds.lua      # C/C++ indent detection, cscope auto-load, tagfunc reset
    ├── man_code/             # man page highlighting on top of nvim's own :Man
    │   ├── init.lua          # parse the code blocks with the section's Tree-sitter grammar
    │   └── structure.lua     # headings, option names and cross-references above the bold marks
    ├── lsp_filter/           # custom per-path LSP gating module
    │   ├── init.lua          # public API, LspAttach gating, registry persistence
    │   ├── rules.lua         # rule engine (within/contains → disable/diagnostics_off)
    │   └── util.lua          # path / JSON helpers (atomic writes)
    └── plugins/
        ├── dap.lua           # nvim-dap + dap-view + disassembly, GDB adapters, keymaps, commands
        ├── dap_languages.lua # debug support for the languages that are not GDB targets
        ├── clangd.lua        # clangd cmd + dynamic -j, inlay hints off
        ├── cscope.lua        # cscope_maps.nvim + Telescope, <leader>i* navigation
        ├── asm.lua           # asm/linkerscript parsers + at-line-start? cpp-injection predicate
        ├── ansi_color.lua    # baleia.nvim: ANSI colours in the gdb console, :BaleiaColorize elsewhere
        ├── diagnostics.lua   # CursorHold auto floating diagnostics
        ├── discord_rpc.lua   # Discord Rich Presence over the IPC socket, no plugin
        ├── elixir.lua        # elixir/heex/eex Tree-sitter parsers
        ├── formatting.lua    # oxfmt as the conform formatter for web filetypes, taplo for toml
        ├── fs_refresh.lua    # external change auto-reload + :FsRefresh
        ├── hlslens.lua       # nvim-hlslens: match index beside the search hit
        ├── lean.lua          # lean.nvim for Lean 4, infoview at the bottom
        ├── lsp_filter.lua    # wires up lsp_filter + <leader>cF* keys
        ├── mason.lua         # Mason packages this config expects (ensure_installed)
        ├── im_control.lua    # Korean langmap + IME auto-reset
        ├── imstate.lua       # Caps Lock + fcitx5 lualine indicators
        ├── lualine.lua       # full path + encoding/format flag
        ├── git_tag.lua       # git describe tag beside the branch
        ├── mini-files.lua    # <CR> = open file & close / enter dir
        ├── noice.lua         # noice.nvim with the search-count message off (hlslens shows it)
        ├── snacks.lua        # bigfile 5 MiB, picker shows hidden + ignored
        ├── colorscheme.lua   # selects spaceduck (+ alternate schemes installed)
        ├── markview.lua      # markdown rendering (markview.nvim)
        ├── neovide.lua       # Neovide GUI settings + zoom/paste keys
        └── neovide-ime.lua   # neov-ime.nvim, loaded only under Neovide
```

---

## Features in detail

### Bootstrap & base (`init.lua`, `lua/config/lazy.lua`)

`init.lua` only requires `config.lazy`, which clones lazy.nvim's stable branch on first run, imports LazyVim plus `lua/plugins/`, and sets:

- `defaults.lazy = false` — plugins load eagerly at startup.
- `defaults.version = false` — latest commits, not tagged releases.
- `install.colorscheme = { "gruvbox-material", "tokyonight", "noctis" }` — post-install fallback list; the active scheme is `spaceduck`.
- `checker.enabled = true`, `checker.notify = false` — silent background update checks.
- Built-in `gzip`, `tarPlugin`, `tohtml`, `tutor`, `zipPlugin` are disabled.

### Editor options (`lua/config/options.lua`)

- `number = true`, `relativenumber = false`.
- `tags = "./tags;,tags;"` — a `tags` file beside the current file, then upward through parents.
- `guicursor` — block in normal/visual/command, thin bar in insert, with blink timing.
- `modeline = false`, `swapfile = false`.
- `whichwrap` extended so `h`, `l` and the arrow keys wrap across lines.
- `vim.filetype.add` — `.S`/`.s`/`.sx` pinned to `asm`, `.lds` and `*.lds.S` to `ld` (see the highlighting section).

### Linux kernel C workflow (`lua/config/autocmds.lua`, `lua/plugins/clangd.lua`, `lua/plugins/cscope.lua`)

- **Indentation** — a `.clang-format` found upward sets the width (`IndentWidth`, `UseTab`, `TabWidth`, or the `BasedOnStyle` default); a project `.editorconfig` wins over it. With neither, the buffer decides: more of its first 2000 lines starting with a tab than with two or more spaces means 8-column tabs (`noexpandtab`), otherwise 4 spaces with `tabstop = 8`. That fallback covers kernel trees older than v4.17, which ship no `.clang-format`. Only buffer options change; existing whitespace is never rewritten, and none of this depends on clangd. `list = true` and `vim.b.autoformat = false` apply in every case.
- **clangd** runs as `clangd --background-index --clang-tidy --completion-style=detailed --header-insertion=never --pch-storage=disk --background-index-priority=background --limit-results=200 --limit-references=2000 -j=<N>`, with `<N>` half the logical CPUs (at least 1). Inlay hints are off.
- **cscope** — `cscope_maps.nvim` with the Telescope picker under `<leader>i`; its own default mappings are disabled. On reading a `*.c`/`*.h`/`*.S` file, the nearest `cscope.out` found upward is added once per session.
- **`<C-]>` → tags** — on `LspAttach` to `c`/`cpp`/`h` buffers the LSP `tagfunc` is cleared, so `<C-]>` uses the `tags` file. Generate one with `make tags`.

### Low-level / cpp-preprocessed highlighting (`lua/plugins/asm.lua`, `after/queries/{asm,c,cpp}/injections.scm`)

Kernel low-level sources mix languages in one file. The right grammar is injected into each embedded region, and filetypes are pinned so the parsers run:

- **cpp in assembly** — the `asm` grammar treats every `#` line as a comment. `after/queries/asm/injections.scm` injects the C grammar into `#` directive lines, so `#define`/`#include`/`#ifdef` and macro names read as C; the rest of the line stays assembly.
- **`#at-line-start?` predicate** (registered in `asm.lua`) restricts that to `#` leading a line, so a trailing `# else branch` comment stays a comment. The query fails without the predicate, so the two files travel together.
- **assembly in C/C++** — `after/queries/c/injections.scm` and `cpp/injections.scm` inject the `asm` grammar into `asm("…")` / `__asm__(…)` bodies, each string piece independently so multi-line and adjacent-literal blocks read cleanly. `cpp` is included because kernel `*.h` headers are detected as `cpp`.
- **filetype pinning** — `.S`/`.s`/`.sx` are forced to `asm` (Neovim otherwise flips files with `.macro`/`.title` to `vmasm`, which has no parser); `.lds` and `*.lds.S` map to `ld`.
- **parsers** — `asm`, `c`, `cpp`, `linkerscript`, `devicetree` (and `elixir`, `heex`, `eex` from `elixir.lua`) are in `ensure_installed`.
- **linker scripts** — `*.lds`, `*.ld` and `*.lds.S` use the `linkerscript` grammar. It has no `#` handling, so cpp directive lines lose highlighting; accepted, because the `asm` fallback mis-tokenises `SECTIONS`/`ALIGN`/output sections instead (about 12% vs 18% error nodes on a real `vmlinux.lds.S`).
- **device trees** — `*.dts`/`*.dtsi` use `devicetree`, which handles cpp directives natively.

Known ceiling: this is injection, not preprocessing. `#if 0 … #endif` bodies are still highlighted, and an assembler directive inside a `#define` body is tokenised as C.

### Man pages (`after/ftplugin/man.lua`, `lua/man_code/`)

nvim's `:Man` paints roff's bold and italic as extmarks at priority 4096, above anything a syntax file can say, so `syntax/man.vim`'s distinctions never reached the screen. The ftplugin runs two passes after the page is rendered:

- **code** (`lua/man_code/init.lua`) — every indented run is tested for code density, cut to the lines that open and close like code, and parsed with the grammar the section implies (`c` for 0/2/3/4/5/7/9 and the `3p`/`3type`/`3const`/`3head`/`3attr` variants; any other suffix is tried as a grammar name). A block that parses mostly as errors is prose and skipped; one that runs into prose is shrunk back to before the first error and retried. Captures are painted at priority 5000. Bounded at 800 lines per block and 100 ms per page.
- **structure** (`lua/man_code/structure.lua`) — header, footer, section headings, subheadings, option names and `name(section)` cross-references are re-marked at 5200 so the colorscheme's `man*` groups apply. A bold function name followed by `()` has the bold extended over the parentheses.
- **window** — `number`, `relativenumber` and `signcolumn` follow the global values (the stock ftplugin turns them off), `cursorline` is off, `scrolloff` is 4.

### Debugging (`lua/plugins/dap.lua`, `lua/dbg/`)

The debug adapter is GDB itself: GDB 14+ ships a DAP interpreter (`gdb -i dap`), so `nvim-dap` talks to the same GDB that loads your `~/.gdbinit`, pwndbg and any Python tooling. Nothing goes through GDB/MI or a VS Code adapter.

**Languages.** C, C++ and assembly go through GDB (`lua/plugins/dap.lua`, `lua/dbg/`). Everything else is wired the way its ecosystem wires it, in `lua/plugins/dap_languages.lua`, and none of it touches `lua/dbg/`:

| Language | Debug support | What it brings |
|---|---|---|
| C / C++ / asm | `gdb -i dap` | The panels below, the cross-architecture usermode entries, gdbtools |
| Linux Kernel | `gdb -i dap` (`gdb_kernel`) | The same, plus the kernel-only machinery |
| Python | [`nvim-dap-python`](https://github.com/mfussenegger/nvim-dap-python) on `debugpy` | Its own configurations, venv detection, debugging the test under the cursor |
| Rust | [`rustaceanvim`](https://github.com/mrcjkb/rustaceanvim) on `codelldb` | `:RustLsp debuggables`, which finds the cargo targets itself, and LLDB's Rust formatters |
| JavaScript / TypeScript | `js-debug-adapter` | `pwa-node`/`pwa-chrome`/`pwa-msedge`, source maps, `tsx`/`ts-node` for a `.ts` file |
| Elixir | [ElixirLS](https://github.com/elixir-lsp/elixir-ls)'s debug adapter, as `mix_task` | `mix test` and `mix run` under the debugger |

Adapters are resolved from Mason's package directory rather than `PATH`. A language with no adapter gets nvim-dap's own *No configuration found* and nothing else. `.vscode/launch.json` is read on demand for every language, comments included. Julia is not offered: `julia-lsp`'s debugger expects a VS Code handshake over named pipes. rustaceanvim runs its own `rust-analyzer`, so `nvim-lspconfig`'s `rust_analyzer` is disabled to keep a second client off the buffer.

**Session context.** `lua/dbg/context.lua` classifies every session as `linux_kernel`, `native` (GDB on a userspace program) or `managed` (everything else), from the adapter type or a `dbg_profile` on the configuration. A GDB session gets the full panel set and winbar (*Registers(G)*, *Memory(M)*, *Mappings(V)*, *Control flow(F)*, *Target(I)*, *gdb console(R)*). A managed session gets `nvim-dap-view` exactly as it ships; none of the GDB machinery attaches, and GDB-only views and commands (Registers, Memory, Mappings, disassembly, the control-flow graph, `:DbgState`, `:DbgLayout`, `:DbgSafeMem`, `:DbgInline`, `<leader>dF`) are refused with a note.

**Running a program.** Launch configurations ask for the executable and then its command line, split with shell quoting rules. Both prompts remember the last answer, and `<leader>dc` with no session replays the last run without asking; `<leader>dn` picks a different configuration or program.

**Adapters.** `gdb` (launch, launch-and-stop-at-main, attach by PID, two cross-architecture usermode entries) and `gdb_kernel` for remote targets. The kernel adapter picks `<triple>-gdb` when one exists, adds `add-auto-load-safe-path <kernel root>` so `vmlinux-gdb.py` loads, sources gdbtools when found (`$GDBTOOLS_PATH`, walking up from the kernel root, or the checkout gdbtools' `setup.sh` recorded), and passes the full environment through (libuv replaces the environment, so `HOME` and `~/.gdbinit` would otherwise be lost).

**Foreign-architecture userspace.** *Run on QEMU user* asks for the guest binary, arguments and a gdbstub port, starts `qemu-<arch> -g <port> -L <sysroot> <binary>` and attaches, stopped at `_start`. *Attach to a QEMU user gdbstub* connects to one you started yourself. The architecture is the ELF's `e_machine`; the cross gdb, the sysroot (`/usr/<triple>`, left unset for a static binary) and the `qemu-<arch>` all follow from it. x86_64, aarch64 and riscv64 are wired. A QEMU this editor launched is stopped by its port alone when the session ends or Neovim exits; a stub you started is left running.

**Entry address and KASLR.** The launcher records the boot mode and, for a firmware chain, the address the bootloader lands the kernel at, per gdb port; the adapter hands gdbtools that combination rather than the tree's default. A firmware boot gets a hardware breakpoint, since the image is copied to that address after reset. A u-boot chain also loads the bootloader's ELF beside `vmlinux`; UEFI ships no symbols. A direct boot leaves the entry unstated so gdbtools recovers or scans for it. On x86_64 a guest whose KASLR state is not positively off leaves the entry unstated too, because the physical base is randomized; arm64 and riscv64 keep it. KASLR is read from the recorded run, then the guest's `-append`, then `CONFIG_RANDOMIZE_BASE`; a guest that answers none counts as randomized.

**Attaching to a kernel.** After picking the target, `<leader>dq` asks how: attach where the kernel already is, or arm the early-boot machinery (`kearly on`, `kearly bootbreak`, `kearly status`) and stop on the first `head.S` instruction with the MMU off. `kearly kaslr auto` is deliberately not run; type it in the console to stop at the virtual crossing. A breakpoint set while the slide is unknown arms a catcher on the crossing by itself. On x86 the recovery also needs `GDBTOOLS_X86_KASLR` in the adapter's environment. A target without `kearly` is told so.

**A dead gdbstub says so.** The QEMU process the target came from is watched while the session runs; when it disappears the session is disconnected with the reason and the panels stay up showing the last reported state.

**Finding a target.** `<leader>dq` lists QEMU instances exposing a gdbstub, built from `/proc/<pid>/cmdline` of each `qemu-system-*` process: `-gdb`, `-S`, `-kernel`, `-append`, `-M`, `-cpu`. The symbol file comes from `-kernel` (stripping `arch/*/boot/*`, or the image itself when it is an ELF); a firmware-booted guest has no `-kernel` naming Linux, so every other path on the command line is walked up from until a kernel build turns up beside one. The architecture is the symbol file's `e_machine`. The port is confirmed against `/proc/net/tcp`, never by dialling it, because a gdbstub accepts one client. `<leader>dQ` shows the same data with the evidence for every field; anything without evidence is reported as unknown.

**Panels** (`nvim-dap-view`, one bottom window with a winbar): Scopes, Locals+Globals, Watches, Registers, Memory, Mappings, Disassembly, Call stack, Breakpoints, Target, gdb console and Output. The console is nvim-dap's REPL wired to GDB's own interpreter, so `bt`, `vmmap`, `telescope`, `context`, `checksec`, `kearly`, `lx-dmesg` and everything else your GDB and pwndbg know can be typed there; `baleia.nvim` colorizes the ANSI. `<CR>` in normal mode sends the line under the cursor, and on an earlier `dap>` line runs it again; `i`, `a`, `A`, `I` jump to the prompt. The console buffer outlives the session. blink.cmp is off in `dap-repl` buffers; GDB's own completion is `<C-x><C-o>`.

Execution control typed into the console (`c`, `n`, `s`, `ni`, `si`, `finish`, `q`, `kill`) goes through nvim-dap rather than straight to GDB, because sending it directly leaves the panels showing a stale stop and the frame ids go stale. Everything that only inspects state is passed through untouched.

- **Registers** merges the DAP register scope with one `info symbol` sweep, so values that point at something show `<symbol+offset>`. Changed registers are marked. System and vector registers are collapsed into a grid below. `f` filters, `<CR>` opens the value in the hex view.
- **Memory** is a hex view whose source and layout you pick (`t`, `L`, or `:DbgMemory`): any expression or address, a physical address through the QEMU monitor, or a file on disk. Layout: bytes per row or fit-to-window, bytes per group with byte-order toggle, row count, ASCII column, symbol annotation for 8-byte groups. Targets can be pinned and switched. Only presets the target supports are offered.
- **Mappings** parses `vmmap` into a table; `<CR>` opens a region in the hex view.
- **Locals+Globals** puts what the frame owns on the left and what the file owns on the right. GDB publishes only Arguments, Locals and Registers, so the file-scope side is collected from the current compilation unit's symbols, `static` included. A name that cannot be read is not listed; a variable the compiler threw away keeps its row, tagged `opt`.
- **Values where variables are used.** The same values dap-view puts on declaration lines are placed at the end of every visible line that mentions them. `:DbgInline off` turns it off.
- **Target** shows the session and queries whatever applies: `lx-version`, `kearly`, `mmview` for a kernel; `checksec`, `piebase` for userspace.

**Disassembly.** The current instruction is marked by background alone, from the theme's diff colour. When the program counter stands on a branch that will be taken, a connector is drawn to its destination; a fall-through draws nothing; an undecidable condition draws it dim. The decision is per architecture from the registers the target exposes: `cpsr` for aarch64, `eflags` for x86 `jcc`, direct comparison for riscv. Indirect branches (`ret`, `br`, `blr`, `jr`, `jalr`, `jmp *%rax`) resolve from the stopped state. Addresses are computed on fixed-width hex strings, not doubles. The connector is an equal-width prefix on every row, since dap-view sets `statuscolumn = ""` on its panel.

**Builds without `-g`.** Function and instruction breakpoints need no line table, but nvim-dap has no API for them, so the list is kept here and pushed to the session before it runs. `<leader>dF` breaks on a symbol or a `0x` address, with or without a session; `<leader>dg` lists every breakpoint in a picker. With no line table `<leader>dO` and `<leader>di` switch to instruction granularity and say so once.

**Frame selection.** nvim-dap selects the first frame with a source; on a binary without debug info that silently selects the caller. The selection is put back on frame 0 before anything reads it, so registers, scopes and the console describe the same frame. When that frame has no source the stale marker is removed and the panel switches to the disassembly, unless you are typing in the console.

**Capabilities are decided up front.** `:DbgState` reports adapter, launch or attach, kernel/userspace/bare metal, and whether the program carries embedded DWARF, a separate debug file or none, then answers yes or no for line breakpoints, source stepping, function breakpoints, instruction breakpoints, disassembly and the QEMU monitor, with a reason for every no. On each attach GDB is asked which symbols resolve, which commands exist, which registers the architecture has, and whether the monitor answers; a kernel is recognised by `init_task`/`linux_banner`/`swapper_pg_dir`, userspace by `__libc_start_main`/`environ`/`main_arena`, anything else is bare metal.

**Memory reads are guarded.** A debug read of a guest address outside RAM makes QEMU dispatch into a device model, which has taken the VM down. Before reading, the address is checked with `monitor gva2gpa` and `monitor gpa2hva`, with the monitor first aimed at the core the session is stopped on. RAM is read normally, a physical-RAM address that is not a live virtual one is read through `monitor xp`, and a device region or hole is refused with the reason. Where the stopped core cannot translate, the other cores are asked before answering "unmapped" (an SMP guest in early boot has cores in different regimes). The first page decides how the window is read; the pages after it can only veto, since the hex view reads up to 8 KiB. `o` reads anyway, `:DbgSafeMem off` disables the guard, and it is inert without a QEMU monitor.

**Stopping detaches.** GDB's DAP maps `terminate` to `kill`, which ends a QEMU guest, so `<leader>dt` disconnects without terminating for attach sessions and kills only launched processes. `<leader>dT` is the explicit kill.

**Layout follows the terminal.** The only measurement is Neovim's `columns` and `lines`, so a font-size change counts as a resolution change. Below the threshold everything lives in the bottom panel's tabs; above it a side column carries one panel at full height, Registers by default, and the bottom bar runs the whole width underneath.

| Terminal | Mode | Side column | Panels stacked | Source width |
|---|---|---|---|---|
| 120x32 | compact | — | 0 | 120 |
| 140x36 | wide | 42 | 1 | 98 |
| 200x50 | wide | 60 | 1 | 140 |
| 240x60 | wide | 72 | 1 | 168 |
| 280x70 | wide | 78 | 2 | 202 |
| 320x90 | wide | 78 | 3 | 242 |

A second panel is stacked only once the first still gets every row it needs. Sizes are re-applied on every stop and whenever a window opens or closes, because dap-view reflows the column. `]p`/`[p` rotate which panel the column shows. `:DbgLayout auto|wide|compact` overrides the mode; `:DbgLayoutReset` rebuilds the windows without touching the session.

**Windows.** Source always opens in a source window: nvim-dap's fallback is the previous window, which is a pinned panel when stepping from the console and fails with `E1513`, so a `switchbuf` function picks a window holding an ordinary file, splitting one off if needed. Panel buffers and debugger-owned windows are registered in one place (`lua/dbg/panel.lua`), with a `WinClosed` hook dropping handles. Starting a session records the layout and opens the panels; ending one closes nothing. `:DbgClose` restores the recorded layout and drops the sources the debugger listed on its way through (that glibc header among them) unless edited or still open. `<leader>du` closes the panel without restoring.

**Messages.** Starting, exiting (with the exit code), detaching and unexpected stops go through `vim.notify`, as does a breakpoint that never bound, with why; an executable without `.debug_*` sections is reported as built without `-g`. `:DbgLog` shows everything reported, including what scrolled past.

### `lsp_filter` — per-path LSP gating (`lua/lsp_filter/`, `lua/plugins/lsp_filter.lua`)

Turns LSP servers off for chosen files or directories, for silencing generated or vendored subtrees in a large tree.

- Actions: `disable` (detach the client) or `diagnostics_off` (keep the server, hide its diagnostics).
- Rules match by `within` (path prefix) or `contains` (a path segment anywhere), scoped to servers (default `clangd`, `"*"` for all, or a custom list via the advanced add).
- Rules persist at `~/.local/share/nvim/lsp_filter/rules.json` (`stdpath("data")`, outside every repo). Writes are atomic and refuse to clobber a symlink; a malformed registry aborts the write.
- `<leader>cFe` edits the registry; saving reloads it. `<leader>cFt` toggles the filter for the session only.
- Project marker files (`.nvim-lsp-filter.json`, searched upward) are supported but off by default (`setup({ markers_enabled = true })`).

#### Recipe — turn clangd off for a directory (no git footprint)

1. Open any file inside the directory.
2. Press `<leader>cFd` and pick the directory (or an ancestor); `<leader>cFf` for just the current file; `<leader>cFa` to type a path and choose server scope and action.
3. The rule lands in `rules.json` under `stdpath("data")`, so neither the project's git nor this repo's ever sees it, and it persists across restarts.

| Want to… | Do this |
|----------|---------|
| Toggle the whole filter off for now | `<leader>cFt` (session only) |
| Remove a rule permanently | `<leader>cFe` → delete the line → `:w` |
| Re-read the registry after editing it elsewhere | `<leader>cFr` |
| See which rule gates the current buffer | `<leader>cFl` |

### Korean input-method integration (`lua/plugins/im_control.lua`, `lua/plugins/imstate.lua`)

- **`langmap`** maps Dubeolsik Hangul jamo to their QWERTY keys, so Normal-mode commands work while the OS IME emits Hangul.
- **Auto-reset** — on `InsertLeave` and `FocusGained` the IME is forced back to English. Backend detected at startup: `fcitx5-remote -c` (Linux), `im-select.exe` (Windows), or `issw` (macOS); with none, only the `langmap` applies. It never switches you into Korean.
- **Statusline indicators** — a 200 ms timer polls the Caps Lock LED and `fcitx5-remote -n`, exposing `vim.g.caps_state` and `vim.g.im_state`. Each lualine component is added only when its backend exists: `󰬈 CAPS`, and `한` for Hangul, otherwise `EN`/`en` with the case mirroring Caps Lock.

### UI & appearance

- **`spaceduck`** (`colors/spaceduck.lua`) — hand-written theme with broad Treesitter coverage and a dedicated C/C++ palette. Transparent in the terminal, opaque under Neovide; needs true color. It also defines `vim.g.spaceduck_lualine`, which `lualine.lua` does not wire up (the statusline keeps LazyVim's `auto` theme). `colorscheme.lua` selects it and installs `lush.nvim` / `noctis.nvim` / `gruvbox-material` as alternates.
- **lualine** (`lualine.lua`) — the full path, never truncated, and an encoding/line-ending flag (`UTF-8/LF`, `UTF-8+BOM/CRLF`) on the right.
- **Git tag** (`git_tag.lua`) — after the branch, the tag `git describe --tags` resolves to: `v6.12.95` on the tag, `v6.12.95+12` twelve commits past it. Async per repository root, cached 10 s. Kernel trees tag releases as `v<version>`, so this reads as the tree's version, on a detached HEAD too.
- **hlslens** (`hlslens.lua`) — `[current/total]` beside the nearest search match after `n`/`N`/`*`/`#`/`g*`/`g#` and on leaving `/` or `?`. `noice.lua` turns off noice's own search-count message so the two do not double up.
- **mini.files** (`mini-files.lua`, LazyVim `editor.mini-files` extra) — `<CR>` opens a file and closes the explorer, or enters a directory.
- **Snacks** (`snacks.lua`) — `bigfile` at 5 MiB; explorer/files/grep show hidden and gitignored files (noisy in a kernel tree); the explorer's `watch` is pinned on.
- **markview** (`markview.lua`) — in-buffer Markdown rendering, default settings.
- **Diagnostics** (`diagnostics.lua`) — line diagnostics open in a rounded, non-focusable float on `CursorHold`, source shown, and close on cursor move, insert or buffer hide.
- **Discord presence** (`discord_rpc.lua`) — a self-contained Rich Presence client over Discord's IPC socket, on by default on Linux; `<leader>uD` / `:DiscordRpcToggle` toggles it, `:DiscordRpcStatus` reports. It shows "Editing in Neovim" and elapsed time, no file or workspace names.
- **ANSI colours** (`ansi_color.lua`) — `baleia.nvim` colorizes the gdb console; `:BaleiaColorize` does the same for any buffer holding escape codes.
- **Lean** (`lean.lua`) — `lean.nvim` for Lean 4 with the infoview at the bottom, unicode abbreviations on `\`, and a green accomplished-goal sign kept across colorscheme changes.

### External change detection & refresh (`lua/plugins/fs_refresh.lua`)

LazyVim only runs `:checktime` on focus and terminal events, so files rewritten while the editor keeps focus (an agent, `git` in another terminal, a build) are missed. This module makes detection unconditional:

- **Buffers** — a 2 s poll plus `BufEnter`/`CursorHold`/`CursorHoldI` run `:checktime`; unmodified buffers reload (`autoread`), conflicts still raise W12. A notification names what reloaded, batched.
- **snacks explorer** — already watches expanded directories; collapsed levels re-scan on `:FsRefresh`.
- **mini.files** — re-read on the same tick, skipped while an explorer holds pending manual edits.
- **`:FsRefresh`** / `<leader>uR` — `checktime` over all buffers, a full re-scan of every open explorer tree, and a mini.files re-read.

### ChKeys — on-screen keystroke display (`lua/chkeys.lua`)

Captures keys via `vim.on_key` and renders them in rounded floats at the bottom-right, dismissed after 1.6 s. Enables the kitty keyboard protocol on kitty, WezTerm, foot, ghostty and rio for modifier detection, shows a `한` indicator when `vim.g.im_state == "한"`, writes nothing to disk. `<leader>uK` or `:ChKeysToggle`. Under Neovide it uses one window per key.

### Neovide GUI (`lua/plugins/neovide.lua`, `lua/plugins/neovide-ime.lua`)

Guarded by `if vim.g.neovide`. Font `CaskaydiaCove_Nerd_Font_Mono:h12:w-1`, 120/5 Hz refresh, short cursor animation, 28 px padding, full opacity, quit confirmation, and the zoom/paste keys below. `neov-ime.nvim` loads only under Neovide.

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
| `<leader>dc` | Run / continue — with no session, replays the last configuration without re-prompting |
| `<leader>dn` | Start a new session, choosing configuration, executable and arguments again |
| `<leader>db` / `<leader>dB` | Toggle breakpoint / conditional breakpoint |
| `<leader>dF` | Break on a function name or a `0x` address (works without `-g`) |
| `<leader>dg` | List every breakpoint — line, function and address — in a picker |
| `<leader>dC` | Run to cursor |
| `<leader>di` / `<leader>do` / `<leader>dO` | Step into / over / out — instruction granularity when there is no line table |
| `<leader>dj` / `<leader>dk` | Move down / up the call stack |
| `<leader>dP` | Pause |
| `<leader>dt` | Stop — detaches when attached, terminates a launched process |
| `<leader>dT` | Terminate for real (kills a QEMU guest) |
| `<leader>dl` | Run last configuration |
| `<leader>du` | Toggle the debug panel |
| `<leader>de` / `<leader>dw` | Evaluate under cursor / add a watch |
| `<leader>dr` | Toggle the debug console |
| `<leader>dR` / `<leader>dm` / `<leader>dD` | Registers / hex view / disassembly (GDB sessions only) |
| `<leader>ds` | Target panel (GDB sessions only) |
| `<leader>dq` | Pick a QEMU gdbstub and attach |
| `<leader>dQ` | Report every debug target found on this host, with the evidence |
| `<leader>dPt` / `<leader>dPc` | Debug the Python test method / class under the cursor (python buffers) |
| `<leader>dPr` | Pick a cargo target to debug, `:RustLsp debuggables` (rust buffers) |

Inside the hex view: `t` source, `L` layout, `w` bytes per row, `g` bytes per group, `+`/`-` rows, `]]`/`[[` page, `<CR>` follow pointer, `p`/`x`/`s` pin/unpin/switch, `e` byte order, `A` ASCII column, `N` symbol annotation, `W` width fitting, `a` auto refresh, `o` read past the guard, `r` refresh. Inside Registers: `f` filter, `r` refresh, `<CR>` open the value in the hex view. Inside Locals+Globals: `r` refresh, `f` filter, `<CR>` pin the name to Watches, `K` ask `ksym` what the address on the line is (physical or virtual; it names the address and does not walk it). Inside the side panel: `]p`/`[p` switch panel.

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
| `:DbgKernel` / `:DbgKernelEarly` | `plugins/dap.lua` | Attach to a QEMU gdbstub for a Linux kernel; the second exports `GDBTOOLS_AUTO=1` |
| `:DbgTargets` | `plugins/dap.lua` | Report the debug targets found on this host |
| `:DbgMemory [expr\|file]` | `plugins/dap.lua` | Open the hex view |
| `:DbgRegisters` / `:DbgMappings` | `plugins/dap.lua` | Open the register / mapping panels |
| `:DbgControlFlow` | `plugins/dap.lua` | Show the control-flow graph in the source window; again to go back |
| `:DbgSafeMem on\|off\|auto` | `plugins/dap.lua` | Guard memory reads against QEMU device-region dispatch |
| `:DbgLayout auto\|wide\|compact` | `plugins/dap.lua` | Switch the debugger window layout |
| `:DbgLayoutReset` | `plugins/dap.lua` | Rebuild the debugger windows, leaving the session and breakpoints alone |
| `:DbgBreak [name\|0xADDR]` | `plugins/dap.lua` | Break on a function or an address, no line table needed |
| `:DbgBreakpoints` | `plugins/dap.lua` | List every breakpoint in a picker |
| `:DbgState` | `plugins/dap.lua` | Report what this session supports, and why not when it does not |
| `:DbgClose` | `plugins/dap.lua` | Close every debugger window and restore the previous layout |
| `:DbgInline on\|off` | `plugins/dap.lua` | Show variable values where they are used |
| `:DbgLog` | `plugins/dap.lua` | Everything the debugger reported, including what scrolled past |
| `:ChKeysToggle` | `chkeys.lua` | Toggle the keystroke display |
| `:FsRefresh` | `fs_refresh.lua` | Reload changed buffers + refresh snacks explorer / mini.files |
| `:DiscordRpcToggle` / `:DiscordRpcStatus` | `discord_rpc.lua` | Toggle / report Discord Rich Presence |
| `:BaleiaColorize` | `ansi_color.lua` | Interpret ANSI escape codes in the current buffer as colours |
| `:Cscope` / `:Cs` | `cscope_maps.nvim` | The `<leader>i*` keys wrap `:Cscope find …`; `:Cs` auto-adds databases |

---

## Caveats

- **Background is transparent in the terminal.** `spaceduck` leaves `Normal` unset so the terminal shows through; it paints an opaque background only under Neovide.
- **`<C-]>` does not use LSP** in C/C++/H buffers. Generate `tags` for it to work.
- **Pickers include ignored files.** Build outputs and dotfiles appear in the Snacks sources; noisy in a kernel tree.
- **No swap files**, so no swap-based crash recovery.
- **Unmodified buffers reload silently every 2 s** when their file changes on disk. The reload is undoable and a notification names the file.
- **Autoformat is off for C/C++**, so kernel sources are never reformatted on save.
- **`lsp_filter` rules live outside the repo** at `~/.local/share/nvim/lsp_filter/rules.json`; machine-local, not version-controlled.
- **A QEMU gdbstub takes one client.** While Neovim is attached, a separate `gdb` cannot connect, and vice versa; use the gdb console panel. Discovery never probes a port, and refuses a stub that already has a client.
- **Quitting Neovim mid-session is safe.** Sessions are shut down on the way out, detaching for attach sessions so the guest survives and terminating launched ones.
- **The hex view shows one window at a time.** The header spells out the range and file size; `]]`/`[[` page through it. Symbol annotation is capped at the first 128 values per page.
- **`<leader>dt` detaches.** GDB's DAP `terminate` runs `kill`, which ends the guest; `<leader>dT` is the kill.
- **The memory read guard is on for QEMU targets.** Untranslatable addresses are refused with the reason; `o` overrides once, `:DbgSafeMem off` disables it.
- **Source-line breakpoints need `-g`; symbol breakpoints do not.** Without DWARF, `<leader>db` refuses and points at `<leader>dF`. Build with `-g -O0` for line stepping and locals.
- **Ending a session leaves the windows open.** `<leader>du` closes the panel, `:DbgClose` restores the pre-session layout; both are asked for.
- **Early-boot kernel tooling is not armed by default.** `:DbgKernel` leaves `kearly` inert; `:DbgKernelEarly` exports `GDBTOOLS_AUTO=1` and runs `kearly on`, `kearly bootbreak`, `kearly status`. `bootbreak` resumes the guest from inside the request that ran it, and the session catches up when it lands.
- **An x86 UEFI guest with KASLR on needs a QEMU monitor and a spare debug register per copy of the image.** The EFI stub picks the physical base itself, so gdbtools finds the loaded image by advancing the guest through the monitor and searching RAM, then arms the stub's hand-off in both copies the firmware keeps, one hardware breakpoint each out of the four x86 has.
- **Arming takes seconds, sometimes tens.** `kearly bootbreak` runs the guest from the reset vector to the kernel entry under TCG (KVM is off on x86 so early hardware breakpoints stay deterministic). Measured on this machine:

  | Target | Arming | What the time is |
  |---|---|---|
  | x86_64, firmware boot | 3 s | firmware hands over at a known address |
  | arm64, u-boot | 3 s | same |
  | x86_64, direct boot | 15 s | the decompressor has to pick the entry first |
  | arm64, direct boot | 32 s | the Image magic is scanned for over physical RAM |
  | riscv64, direct boot | 45 s | OpenSBI runs to the hand-off first |
  | x86_64, UEFI + KASLR | 34 s | the image is found in RAM in short steps, then decompressed |

  The session looks stopped at the reset vector for that whole time. That is the arming, not a hang.
- **`<leader>dP` waits a moment in Python and Rust buffers.** It is a prefix of `<leader>dPt` / `<leader>dPc` / `<leader>dPr`, so Neovim holds it for `timeoutlen` (300 ms). `<leader>dPt`/`<leader>dPc` are LazyVim's Python keys; `<leader>dPr` sits under the same prefix for symmetry.

---

## Credits

- **[spaceduck](https://github.com/pineapplegiant/spaceduck)** by *pineapplegiant* — MIT License, "Copyright (c) 2020 pineapplegiant". `colors/spaceduck.lua` is an independent Neovim/Lua re-implementation reusing the palette and name; the upstream author explicitly welcomes ports.
- Built on **[LazyVim](https://github.com/LazyVim/LazyVim)** and **[lazy.nvim](https://github.com/folke/lazy.nvim)** by *folke*.
- Notable third-party plugins: [cscope_maps.nvim](https://github.com/dhananjaylatkar/cscope_maps.nvim), [nvim-dap](https://github.com/mfussenegger/nvim-dap), [nvim-dap-view](https://github.com/igorlfs/nvim-dap-view), [nvim-hlslens](https://github.com/kevinhwang91/nvim-hlslens), [baleia.nvim](https://github.com/m00qek/baleia.nvim), [lean.nvim](https://github.com/Julian/lean.nvim), [markview.nvim](https://github.com/OXY2DEV/markview.nvim), [mini.nvim](https://github.com/nvim-mini/mini.nvim), [snacks.nvim](https://github.com/folke/snacks.nvim), [noice.nvim](https://github.com/folke/noice.nvim), [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim), and [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).
