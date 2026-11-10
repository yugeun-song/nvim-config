# Editor

Editing, Korean input, code search and the key cheat sheet. Specs: `lua/plugins/editor/`, `lua/plugins/formatting.lua`, `lua/plugins/linting.lua`; code: `lua/features/editor/`, `lua/config/options.lua`, `lua/config/keymaps.lua`.

## Editing

Options, motions, the file explorer, formatting, linting, following changes on disk, Open Folder and opening files from other programs.

### What it does

- **Options**: absolute line numbers, `tags = "./tags;"` (searched upward from the buffer, never from the working directory), a bar cursor in Insert mode, no modelines, no swap files (so no swap recovery), `h`, `l` and the arrows wrap across lines; the node, perl and ruby providers are off.
- **Indent stops** (`indent_stop_motion.lua`): in leading spaces, `h`, `l` and the arrows (and the arrows in Insert mode) step by `shiftwidth`, as over a tab; `x` and `dl` still take one space.
- **Prose**: `text`, `plaintex`, `typst`, `gitcommit` and `markdown` buffers wrap but keep spell off (`<leader>us` toggles it); `spelllang = en,cjk` leaves Hangul, Han and kana alone. Language servers are detached from `claude-prompt-*.md`, the file Claude Code opens on Ctrl+G.
- **mini.files**: `<CR>` opens a file and closes the explorer, or enters a directory.
- **Pickers** (`pickers.lua`, `big_files.lua`): the explorer, files and grep include hidden and ignored files, but files and grep skip `.cache` directories; the explorer watches the disk. `<leader>ba` lists every buffer and opens the pick in an editing window. From 5 MiB a file opens as Snacks' `bigfile`.
- **Trouble** (`trouble.lua`): its symbols (`<leader>cs`) and LSP lists (`<leader>cS`) open at the bottom. The line diagnostics on `CursorHold` are in [language servers](lsp.md#line-diagnostics).

### Formatting and linting

| Filetypes | Tool | When |
|---|---|---|
| JavaScript, TypeScript, JSON, CSS, SCSS, Less, HTML | `oxfmt` | format |
| TOML | `taplo` | format |
| C, C++ | `clang-format` | format on request; no autoformat |
| Kotlin | `ktlint`; `detekt` only where the project ships `config/detekt/detekt.yml` or `detekt.yml` | lint on read and save |
| YAML | `yamllint` | lint |

clang-format takes a `.clang-format` or `_clang-format` found upward; without one, the buffer's indentation with function braces on their own line, other braces attached, no one-line functions and includes left in order. yamllint takes the nearest `.yamllint`, `.yamllint.yaml` or `.yamllint.yml`, else `$YAMLLINT_CONFIG_FILE` or `~/.config/yamllint/config`, else `relaxed` without line length. Formatters for other languages are in [languages](lang.md).

### Changes on disk

Every 2 s while Neovim has focus, and on `BufEnter` and `CursorHold`, buffers that reload without a question reload in Normal mode with a notification. A buffer that would ask or pause (unsaved changes, a new or deleted file, `noautoread`) waits for `FocusGained` or `:checktime`. Snacks' `bigfile` buffers are not polled. An open mini.files re-reads a directory it shows when that changes on disk, unless it holds edits not yet synchronized. `:FsRefresh` (`<leader>uR`) also re-scans every snacks explorer.

### Open Folder

`o` on the dashboard, or `<leader>fo`, opens [yazi](https://yazi-rs.github.io/) in a float at the working directory.

- `q` makes the folder yazi is in the working directory: the folder being left gets its session saved (as persistence.nvim does on exit), its buffers close, and the new folder's session comes back, else the dashboard. A modified buffer stops the switch.
- `Q` cancels; `<CR>` on a file opens it, with the working directory at its git root, else its folder.
- `nvim DIR` and `neovide DIR` start the same way: in DIR, with its session or the dashboard, and no directory buffer or explorer (`:e DIR` later still opens the explorer).
- Folders opened either way are remembered (the newest 50) and listed by Projects (`p` on the dashboard, `<leader>fp`) beside the git roots of recent files; picking one switches the same way.

Without `yazi` on PATH, neither the dashboard entry nor `<leader>fo` exists; Projects still works.

### Opening from other programs

A Neovim or Neovide with a UI records its RPC address (`v:servername`) under `running_instances/<pid>` in this configuration's `stdpath("run")` directory (`stdpath("state")` without `$XDG_RUNTIME_DIR`) when its UI attaches or gains focus, and removes it on exit.

`nvim -l scripts/open-at.lua FILE [LINE [COLUMN]]` sends FILE to the most recently focused instance, puts the cursor on LINE and COLUMN, and raises the window of its nearest ancestor that owns one. FILE opens with `:drop` in an editing window (current, else last used; never a float, terminal, explorer or picker), or in a new window at the right. With no instance it starts `neovide -- +LINE FILE`. Nothing listens on TCP.

The raise goes by process id: the windows of one kitty process or foot server share it, so a sibling may come forward, and inside tmux none does.

| Desktop | Window raise through |
|---|---|
| Hyprland | `hyprctl` |
| Sway | `swaymsg` |
| niri | `niri` |
| KDE | `kdotool` |
| X11 | `xdotool` |
| macOS | `osascript` |
| Windows | the [IME helper](util.md#windows-ime-helper)'s `raise-window`, else PowerShell |
| GNOME on Wayland | none: no program may raise a window, so the file opens without it |

heaptrack_gui, Settings > Code Navigation > Custom: `nvim -l <home>/.config/nvim/scripts/open-at.lua %f %l %c`. heaptrack starts it without a shell, so the path must be absolute.

### Keys and commands

| Command | Does |
|---|---|
| `:FsRefresh` | Reload changed buffers and refresh the snacks explorer and mini.files (`<leader>uR`) |

Keys: [keymaps](../keymaps.md#general).

### What it needs

`yazi` for Open Folder; the window tool of the desktop for the raise; `oxfmt`, `taplo` and the linters from Mason ([Mason packages](lsp.md#mason-packages)), `clang-format` from Mason or the system.

### Systems

Everything works on Linux, macOS and Windows. The window raise needs one of the tools above; GNOME on Wayland offers none.

## Korean input

Korean input without leaving Normal mode in Hangul.

### What it does

- **`langmap`** maps the Dubeolsik jamo to their QWERTY keys, so Normal-mode keys typed in Hangul mode work.
- **English on leaving Insert.** On `InsertLeave` and `FocusGained` the IME is set to English, never to Korean, and never while another program has the focus (the switch acts on the foreground window). Tools are tried in order; a failing one hands over to the next, and the last working one goes first:

  | System | Tools, in order |
  |---|---|
  | Linux | `fcitx5-remote -c`, `fcitx-remote -c`, `ibus engine` with `vim.g.ibus_english_engine` (default `xkb:us::eng`); ibus first when `XMODIFIERS` names it |
  | macOS | `macism`, `im-select` or `issw`, to `com.apple.keylayout.ABC` |
  | Windows | the [IME helper](util.md#windows-ime-helper)'s `ime-english`, which keeps the keyboard layout; else `im-select.exe 1033` |
  | WSL | `im-select.exe 1033` |

  On Windows the switch is a line to the running indicator watcher's stdin, starting no process.
- **foot**: its private IME mode sequence (through `nvim_ui_send`) keeps the IME on only in Insert mode.
- **Statusline**: `󰬈 CAPS` while Caps Lock is on, and `한`, `EN` (Caps Lock on) or `en`; no IME mark while the input method does not answer. `vim.g.caps_state` and `vim.g.im_state` hold the same. Every reader pauses while Neovim is unfocused.

  | System | Caps Lock | IME |
  |---|---|---|
  | Linux | `/sys/class/leds/input*::capslock/brightness`, every 200 ms | `fcitx5-remote -n` on Insert enter and leave, focus and idle, and every second |
  | macOS | one `osascript` process | `macism`, `im-select` or `issw` |
  | Windows | one `windows_ime_helper watch-input-state` process reports both on each change | |

### Neovide

[neov-ime.nvim](https://github.com/sevenc-nanashi/neov-ime.nvim) draws the IME preedit in the buffer, only under Neovide. fcitx5 answers every cursor move with an empty preedit, and neov-ime re-sets the cursor on each one, which made `$` forget the end of the line on the next `j` or `k`; only an empty preedit that ends a composition reaches it.

### Keys and commands

None. The langmap and the switch load at start, so keys typed during startup are mapped; the indicators start with the statusline (`VeryLazy`). ChKeys shows `한` too ([UI](ui.md)).

### What it needs

| System | Switch | Indicators |
|---|---|---|
| Linux | `fcitx5`, `fcitx` or `ibus` | `fcitx5-remote` and the sysfs Caps Lock LED |
| macOS | `macism`, `im-select` or `issw` | the same, and `osascript` |
| Windows | Visual Studio's `cl` or clang targeting MSVC, to build the helper; else `im-select.exe` | the helper |
| WSL | `im-select.exe` | as Linux |

### Systems

| Part | Linux | macOS | Windows |
|---|---|---|---|
| `langmap` | yes | yes | yes |
| English on leaving Insert | yes | yes | yes |
| `한`/`EN` indicator | fcitx5 only (ibus and fcitx4 have none) | yes | yes |
| Caps Lock indicator | yes | yes | yes |

WSL counts as Linux, with the switch through `im-select.exe`. `langmap` assumes the Dubeolsik layout.

Over SSH (`SSH_CONNECTION` or `SSH_TTY`) the switch and the indicators are off: they would act on the remote host's IME. foot's sequence still works.

## Code search

Search by a typed pattern instead of the word under the cursor (`code_search/`). `<leader>i/` or `:CodeSearch`: pick a tool this buffer supports, a query kind if it has several, then type the pattern (empty cancels). Hits open in the `<leader>i` Telescope picker; `<C-t>` returns.

| Buffer | Tools |
|---|---|
| C, C++, CUDA, assembly (`.S` `.s` `.asm`), linker scripts, headers | clangd, cscope (nearest `cscope.out`), ctags (`'tags'`), gtags (`global -p`), ripgrep |
| Other files | attached language servers that answer workspace symbols, by name; ripgrep |
| No file | ripgrep from the working directory |

- cscope takes the `<leader>i` kinds (`s g c d t e f i a`) through `:Cscope find`; gtags takes definition, reference, symbol, grep and path.
- ripgrep searches `<leader>/`'s root with its settings and skips index files. Without `rg`, fd searches file names.
- Tools this buffer lacks are not listed; `:CodeSearch` with one reports why and runs nothing. One search at a time: a notice after 1 s, a stop at 30 s.

### Keys and commands

| Command | Does |
|---|---|
| `:CodeSearch [tool [kind [pattern]]]` | Search with a tool this buffer supports (`<leader>i/`) |

### What it needs

`clangd`, `cscope`, `tags` files, GNU Global, `rg` or `fd`, each for its own tool; Telescope (installed with cscope_maps).

## Key cheat sheet

Every key in one searchable list (`key_cheat_sheet.lua`): this configuration's, the plugins' and Neovim's mappings in every mode (the current buffer's included), and Neovim's built-in commands as `$VIMRUNTIME/doc/index.txt` documents them. A mapping shows where it was made; a built-in that a mapping replaces is marked so. The file is read once per session, and nothing loads before `<leader>sK` or `:KeyCheatSheet`.

### Keys and commands

| Command | Does |
|---|---|
| `:KeyCheatSheet` | Every key, mapped and built-in (`<leader>sK`) |

### What it needs

Neovim's `doc/index.txt` for the built-in commands; without it only mappings are listed.

### Systems

Linux, macOS and Windows alike.
