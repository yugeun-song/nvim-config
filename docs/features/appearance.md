# Appearance

Colours, statusline, dashboard, keystroke display, man pages and the Neovide profile. Specs: `lua/plugins/appearance/`; code: `lua/features/appearance/`, `colors/spaceduck-remix.lua`, `after/ftplugin/man.lua`.

## What it does

- **`spaceduck-remix`**: an unofficial derivative of [spaceduck](https://github.com/pineapplegiant/spaceduck) by Guillermo Rodriguez, hand-written in Lua on its palette with a C/C++ palette of its own. True colour; no `Normal` background in a terminal, opaque under Neovide. `:terminal` gets the 16 colours of spaceduck's kitty theme. `gruvbox-material` and `kanagawa.nvim` (transparent floats, no gutter background) are installed beside it.
- **Default colorscheme**: one confirmed in `<leader>uC` stays the default across restarts; confirming `spaceduck-remix` clears that choice.
- **Terminal background** (`terminal_background.lua`): in the TUI the terminal's own background follows `Normal` (OSC 11), so its padding matches; restored on exit and suspend (OSC 111). Skipped inside tmux, screen, Zellij and a nested Neovim.
- **Statusline**: the full path, never shortened; an encoding and line-end flag (`UTF-8/LF`, `UTF-8+BOM/CRLF`); after the branch, the latest tag from `git describe --tags --long` (`v6.12.95`, or `v6.12.95+12` twelve commits past it), read in the background, again after 60 s, on focus and on `:cd`, never while unfocused (`statusline_git_tag.lua`). The IME and Caps Lock indicators come from [input method](input_method.md).
- **Search count**: [nvim-hlslens](https://github.com/kevinhwang91/nvim-hlslens) shows `[current/total]` beside the nearest match after `n`, `N`, `*`, `#`, `g*`, `g#`, `/` and `?`; noice's own search count is off.
- **Dashboard header** (`dashboard_header.lua`): the system's logo left of NVIM, in its brand colour, shifted to the nearest shade that reads at 3:1 against the background. Linux and FreeBSD are named by `/etc/os-release`, macOS and Windows by the system. An unknown system or a narrow window leaves NVIM alone.
- **Pickers** (`snacks_dashboard_and_pickers.lua`): `bigfile` from 5 MiB; the explorer, files and grep include hidden and ignored files, but files and grep skip `.cache` directories; the explorer watches the disk. `<leader>ba` lists every buffer and opens the pick in an editing window.
- **ChKeys** (`keystroke_display.lua`): typed keys float at the bottom right for 1.6 s, with `한` while the IME is in Hangul; one window per key under Neovide. Off at startup. Terminal mode and `input()` and `inputsecret()` prompts are never shown (`excluded_modes`, `hide_cmdtypes`). Nothing is written to disk.
- **Man pages** (`man_page_highlighting/`): `:Man` buffers keep the global `number`, `relativenumber` and `signcolumn`. Code blocks are parsed with the C grammar (sections 0, 2 to 5, 7 and 9, and suffixes such as `3p`; another suffix names its grammar), prose skipped, within 100 ms per page. Headings, options and `name(section)` references are marked above roff's bold.
- **Markdown and ANSI**: markview.nvim renders Markdown; baleia.nvim colours ANSI escapes in the gdb console, and anywhere with `:BaleiaColorize`.

## Neovide

Only under Neovide (`neovide_gui.lua`): text gamma 1.5 and contrast 1.0, 120 Hz (5 Hz idle), a short cursor animation, 28 px padding with none at the bottom, full opacity, quit confirmation. The bottom row stays an empty command line: Neovide stretches the last row into the gap below it, which doubled the statusline.

`neovide/config.toml` holds what Neovide reads itself:

- the font, tuned to match kitty at scale 1: CaskaydiaCove Nerd Font Mono at 11.15 pt, SemiBold for bold. `guifont` stays unset, since it would override that table and cannot name SemiBold;
- `fork = true`: `neovide .` in a terminal returns at once and the editor outlives the terminal; `neovide --no-fork` waits;
- `startup-message-capture = false`: noice keeps the command line and messages from the first redraw.

The IME preedit under Neovide is in [input method](input_method.md#neovide).

## Keys and commands

| Command | Does |
|---|---|
| `:ChKeysToggle` | Toggle ChKeys (`<leader>uK`) |
| `:BaleiaColorize` | Read the current buffer's ANSI escape codes as colours |

Keys: [keymaps](../keymaps.md#general).

## What it needs

`git` for the tag; tree-sitter's `markdown` and `markdown_inline` parsers for markview; `man` for man pages; [Neovide](https://neovide.dev/) for its profile; a Nerd Font for icons.

## Systems

| Part | Linux | macOS | Windows |
|---|---|---|---|
| Colorscheme, statusline, dashboard, ChKeys | yes | yes | yes |
| Terminal background (OSC 11) | yes | yes | yes |
| Man page highlighting | yes | yes | no `man` |
| Neovide profile | yes | yes | yes, settings in `%APPDATA%\neovide` |
