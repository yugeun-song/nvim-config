# Editing

Options, motions, the file explorer, formatting, linting, following changes on disk, Open Folder and opening files from other programs. Specs: `lua/plugins/editing/`; code: `lua/features/editing/`, `lua/config/options.lua`, `lua/config/autocmds.lua`.

## What it does

- **Options**: absolute line numbers, `tags = "./tags;,tags;"`, a bar cursor in Insert mode, no modelines, no swap files (so no swap recovery), `h`, `l` and the arrows wrap across lines; the node, perl and ruby providers are off.
- **Indent stops** (`indent_stop_motion.lua`): in leading spaces, `h`, `l` and the arrows (and the arrows in Insert mode) step by `shiftwidth`, as over a tab; `x` and `dl` still take one space.
- **Prose**: `text`, `plaintex`, `typst`, `gitcommit` and `markdown` buffers wrap but keep spell off (`<leader>us` toggles it); `spelllang = en,cjk` leaves Hangul, Han and kana alone. Language servers are detached from `claude-prompt-*.md`, the file Claude Code opens on Ctrl+G.
- **mini.files**: `<CR>` opens a file and closes the explorer, or enters a directory.
- **Diagnostics**: on `CursorHold` the line's diagnostics open in a float with their source; inlay hints are off. Trouble's symbols (`<leader>cs`) and LSP lists (`<leader>cS`) open at the bottom.

## Formatting and linting

| Filetypes | Tool | When |
|---|---|---|
| JavaScript, TypeScript, JSON, CSS, SCSS, Less, HTML | `oxfmt` | format |
| TOML | `taplo` | format |
| C, C++ | `clang-format` | format on request; no autoformat |
| Kotlin | `ktlint`; `detekt` only where the project ships `config/detekt/detekt.yml` or `detekt.yml` | lint on read and save |
| YAML | `yamllint` | lint |

clang-format takes a `.clang-format` or `_clang-format` found upward; without one, the buffer's indentation with function braces on their own line, other braces attached, no one-line functions and includes left in order. yamllint takes the nearest `.yamllint`, `.yamllint.yaml` or `.yamllint.yml`, else `$YAMLLINT_CONFIG_FILE` or `~/.config/yamllint/config`, else `relaxed` without line length. Formatters for other languages are in [languages](languages.md).

## Changes on disk

Every 2 s while Neovim has focus, and on `BufEnter` and `CursorHold`, the buffers without unsaved changes are checked in Normal mode and reload with a notification. A buffer with unsaved changes is left to LazyVim's check on `FocusGained` and to `:checktime`, which ask (W12) rather than take the next key as the answer. An open mini.files re-reads a directory it shows when that changes on disk, unless it holds edits not yet synchronized. `:FsRefresh` (`<leader>uR`) also re-scans every snacks explorer.

## Open Folder

`o` on the dashboard, or `<leader>fo`, opens [yazi](https://yazi-rs.github.io/) in a float at the working directory.

- `q` makes the folder yazi is in the working directory: the folder being left gets its session saved (as persistence.nvim does on exit), its buffers close, and the new folder's session comes back, else the dashboard. A modified buffer stops the switch.
- `Q` cancels; `<CR>` on a file opens it, with the working directory at its git root, else its folder.
- `nvim DIR` and `neovide DIR` start the same way: in DIR, with its session or the dashboard, and no directory buffer or explorer (`:e DIR` later still opens the explorer).
- Folders opened either way are remembered (the newest 50) and listed by Projects (`p` on the dashboard, `<leader>fp`) beside the git roots of recent files; picking one switches the same way.

Without `yazi` on PATH, neither the dashboard entry nor `<leader>fo` exists; Projects still works.

## Opening from other programs

A Neovim or Neovide with a UI records its RPC address (`v:servername`) under `running_instances/<pid>` in this configuration's `stdpath("run")` directory (`stdpath("state")` without `$XDG_RUNTIME_DIR`) when its UI attaches or gains focus, and removes it on exit.

`nvim -l scripts/open-at.lua FILE [LINE [COLUMN]]` sends `:drop FILE` to the most recently focused instance, puts the cursor on LINE and COLUMN, and raises the window of its nearest ancestor that owns one. With no instance it starts `neovide -- +LINE FILE`. Nothing listens on TCP.

| Desktop | Window raise through |
|---|---|
| Hyprland | `hyprctl` |
| Sway | `swaymsg` |
| niri | `niri` |
| KDE | `kdotool` |
| X11 | `xdotool` |
| macOS | `osascript` |
| Windows | the [IME helper](windows_platform.md#windows-ime-helper)'s `raise-window`, else PowerShell |
| GNOME on Wayland | none: no program may raise a window, so the file opens without it |

heaptrack_gui, Settings > Code Navigation > Custom: `nvim -l <home>/.config/nvim/scripts/open-at.lua %f %l %c`. heaptrack starts it without a shell, so the path must be absolute.

## Keys and commands

| Command | Does |
|---|---|
| `:FsRefresh` | Reload changed buffers and refresh the snacks explorer and mini.files (`<leader>uR`) |

Keys: [keymaps](../keymaps.md#general).

## What it needs

`yazi` for Open Folder; the window tool of the desktop for the raise; `oxfmt`, `taplo` and the linters from Mason ([external programs](external_programs.md)), `clang-format` from Mason or the system.

## Systems

Everything works on Linux, macOS and Windows. The window raise needs one of the tools above; GNOME on Wayland offers none.
