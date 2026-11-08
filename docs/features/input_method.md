# Input method

Korean input without leaving Normal mode in Hangul. Specs: `lua/plugins/input_method/`; code: `lua/features/input_method/`.

## What it does

- **`langmap`** maps the Dubeolsik jamo to their QWERTY keys, so Normal-mode keys typed in 한글 work.
- **English on leaving Insert.** On `InsertLeave` and `FocusGained` the IME is set to English, never to Korean, and never while another program has the focus (the switch acts on the foreground window), by the first tool found:

  | System | Tools, in order |
  |---|---|
  | Linux | `fcitx5-remote -c`, `fcitx-remote -c`, `ibus engine` with `vim.g.ibus_english_engine` (default `xkb:us::eng`); ibus first when `XMODIFIERS` names it |
  | macOS | `macism`, `im-select` or `issw`, to `com.apple.keylayout.ABC` |
  | Windows | the [IME helper](windows_platform.md#windows-ime-helper)'s `ime-english`, which keeps the keyboard layout; else `im-select.exe 1033` |
  | WSL | `im-select.exe 1033` |

  On Windows the switch is a line to the running indicator watcher's stdin, starting no process.
- **foot**: its private IME mode sequence keeps the IME on only in Insert mode.
- **Statusline**: `󰬈 CAPS` while Caps Lock is on, and `한`, `EN` (Caps Lock on) or `en`. `vim.g.caps_state` and `vim.g.im_state` hold the same. Every reader pauses while Neovim is unfocused.

  | System | Caps Lock | IME |
  |---|---|---|
  | Linux | `/sys/class/leds/input*::capslock/brightness`, every 200 ms | `fcitx5-remote -n` on Insert enter and leave, focus and idle, and every second |
  | macOS | one `osascript` process | `macism`, `im-select` or `issw` |
  | Windows | one `windows_ime_helper watch-input-state` process reports both on each change | |

## Neovide

[neov-ime.nvim](https://github.com/sevenc-nanashi/neov-ime.nvim) draws the IME preedit in the buffer, only under Neovide. fcitx5 answers every cursor move with an empty preedit, and neov-ime re-sets the cursor on each one, which made `$` forget the end of the line on the next `j` or `k`; only an empty preedit that ends a composition reaches it.

## Keys and commands

None: the switch and the indicators run by themselves from `VeryLazy`. ChKeys shows `한` too ([appearance](appearance.md)).

## What it needs

| System | Switch | Indicators |
|---|---|---|
| Linux | `fcitx5`, `fcitx` or `ibus` | `fcitx5-remote` and the sysfs Caps Lock LED |
| macOS | `macism`, `im-select` or `issw` | the same, and `osascript` |
| Windows | Visual Studio's `cl` or clang targeting MSVC, to build the helper; else `im-select.exe` | the helper |
| WSL | `im-select.exe` | as Linux |

## Systems

| Part | Linux | macOS | Windows |
|---|---|---|---|
| `langmap` | yes | yes | yes |
| English on leaving Insert | yes | yes | yes |
| `한`/`EN` indicator | fcitx5 only (ibus and fcitx4 have none) | yes | yes |
| Caps Lock indicator | yes | yes | yes |

WSL counts as Linux, with the switch through `im-select.exe`. `langmap` assumes the Dubeolsik layout.
