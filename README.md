# nvim-config

A [LazyVim](https://www.lazyvim.org/)-based Neovim configuration tuned for **Linux kernel / C development**, with a few personal extras: a custom per-path LSP gate, Korean input-method integration, an on-screen keystroke display, a hand-written colorscheme, and Neovide GUI settings.

The config is primarily targeted at Linux. Several features (the Korean IME reset, the Windows/macOS branches) are cross-platform, but the kernel workflow, the Caps Lock indicator, and the GUI font expect a Linux desktop.

---

## Highlights

- **LazyVim base.** Plugins are managed by [lazy.nvim](https://github.com/folke/lazy.nvim); the LazyVim distribution is imported as the foundation, and everything under `lua/plugins/` layers on top.
- **Linux kernel coding style.** C/C++ buffers get 8-wide hard tabs (`noexpandtab`), visible whitespace, and autoformat disabled so kernel sources are never reflowed on save.
- **clangd, cscope & tags wired for big trees.** clangd runs with kernel-friendly flags and dynamic parallelism; cscope databases auto-load; `<C-]>` is redirected to the `tags` file instead of LSP.
- **Custom `lsp_filter` module.** Disable clangd (or any server) per file/directory via persisted rules — useful for excluding noisy generated files from a kernel tree.
- **Korean IME integration.** A Dubeolsik → QWERTY `langmap` keeps Normal-mode commands working while the OS IME is in Hangul, the IME auto-resets to English on leaving Insert mode, and the statusline shows live fcitx5 / Caps Lock state.
- **ChKeys.** A built-in keystroke caster for screencasts/demos.
- **`spaceduck` colorscheme + Neovide profile.** A hand-written theme (transparent in the terminal, opaque under Neovide) plus a complete Neovide GUI setup.

---

## Requirements

| Group | Tool | Why |
|-------|------|-----|
| **Core (required)** | Neovim **0.10+** | The config uses `vim.uv`, `vim.fs.joinpath`, and other recent APIs. |
| | `git` | Bootstraps lazy.nvim on first launch and clones plugins. |
| | C compiler + `make` | Treesitter parsers are compiled locally. |
| | Network access | Needed on the first launch to fetch lazy.nvim and plugins. |
| **Search / UI (recommended)** | `ripgrep` (`rg`), `fd` | Backends for the Snacks picker / grep. |
| | A **Nerd Font** | Icons, statusline glyphs, the Caps Lock glyph, markview rendering. |
| **C / kernel workflow** | `clangd` | C/C++ language server (launched with kernel-friendly flags). |
| | `cscope` | Symbol navigation; databases are auto-loaded. |
| | `universal-ctags` | Generates the `tags` file that `<C-]>` jumps through. |
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

---

## Repository structure

```
nvim-config/
├── init.lua                  # entry point → require("config.lazy")
├── lazy-lock.json            # plugin version lockfile
├── lazyvim.json              # enabled LazyVim extras (mini.files) + version state
├── .neoconf.json             # lua_ls / neodev types for editing this config
├── stylua.toml               # StyLua style for the config's own Lua (2-space, 120 col)
├── colors/
│   └── spaceduck.lua         # hand-written "spaceduck" colorscheme (+ lualine theme)
└── lua/
    ├── chkeys.lua            # on-screen keystroke display (ChKeys)
    ├── config/
    │   ├── lazy.lua          # lazy.nvim + LazyVim bootstrap
    │   ├── options.lua       # editor options (tags, guicursor, no swap/modeline)
    │   ├── keymaps.lua       # ChKeys setup + <leader>uK toggle
    │   └── autocmds.lua      # kernel coding style, cscope auto-load, tagfunc reset
    ├── lsp_filter/           # custom per-path LSP gating module
    │   ├── init.lua          # public API, LspAttach gating, registry persistence
    │   ├── rules.lua         # rule engine (within/contains → disable/diagnostics_off)
    │   └── util.lua          # path / JSON helpers (atomic writes)
    └── plugins/
        ├── clangd.lua        # clangd cmd + dynamic -j, inlay hints off
        ├── cscope.lua        # cscope_maps.nvim + Telescope, <leader>i* navigation
        ├── diagnostics.lua   # CursorHold auto floating diagnostics
        ├── fs_refresh.lua    # external change auto-reload + :FsRefresh
        ├── lsp_filter.lua    # wires up lsp_filter + <leader>cF* keys
        ├── im_control.lua    # Korean langmap + IME auto-reset
        ├── imstate.lua       # Caps Lock + fcitx5 lualine indicators
        ├── lualine.lua       # full path + encoding/format flag
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

### Linux kernel C workflow (`lua/config/autocmds.lua`, `lua/plugins/clangd.lua`, `lua/plugins/cscope.lua`)

- **Coding style** — for `c`/`cpp` buffers: `tabstop = shiftwidth = 8`, `expandtab = false`, `softtabstop = 0`, `list = true`, and `vim.b.autoformat = false` (no clang-format-on-save). This matches the kernel's `Documentation/process/coding-style.rst`.
- **clangd** is launched as `clangd --background-index --clang-tidy --completion-style=detailed --header-insertion=never -j=<N>`, where `<N>` is **half the logical CPUs** (at least 1, so it's host-dependent). `--header-insertion=never` avoids auto-inserting `#include`s, which matters for kernel code. Inlay hints are disabled.
- **cscope** — `cscope_maps.nvim` (with a Telescope picker) provides navigation under the `<leader>i` prefix; its own default mappings and tag keymap are disabled so only the explicit bindings apply. On reading a `*.c`/`*.h`/`*.S` file, the nearest `cscope.out` found upward is auto-added once per session.
- **`<C-]>` → tags, not LSP** — on `LspAttach` to `c`/`cpp`/`h` buffers the LSP `tagfunc` is cleared, so `<C-]>` jumps through the `tags` file (ctags) instead of LSP go-to-definition. This is a deliberate override; generate a `tags` file (`make tags`) to use it.

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
- **`example.lua` is inert** (`if true then return {} end`) — it's the LazyVim onboarding template and configures nothing.

---

## Credits

- **[spaceduck](https://github.com/pineapplegiant/spaceduck)** by *pineapplegiant* — MIT License, "Copyright (c) 2020 pineapplegiant". `colors/spaceduck.lua` here is an independent Neovim/Lua re-implementation that reuses the original spaceduck color palette and theme name. The upstream theme is MIT-licensed and its author explicitly welcomes ports.
- Built on **[LazyVim](https://github.com/LazyVim/LazyVim)** and **[lazy.nvim](https://github.com/folke/lazy.nvim)** by *folke*.
- Notable third-party plugins: [cscope_maps.nvim](https://github.com/dhananjaylatkar/cscope_maps.nvim), [markview.nvim](https://github.com/OXY2DEV/markview.nvim), [mini.nvim](https://github.com/nvim-mini/mini.nvim), [snacks.nvim](https://github.com/folke/snacks.nvim), [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim), and [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).
