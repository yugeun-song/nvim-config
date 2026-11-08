# Help

What the running configuration can tell about itself. Specs: `lua/plugins/help/`; code: `lua/features/help/`, `lua/features/feature_status.lua`, every `lua/features/*/health.lua`.

## What it does

- **Key cheat sheet** (`key_cheat_sheet.lua`): every key in one searchable list: this configuration's, the plugins' and Neovim's mappings in every mode (the current buffer's included), and Neovim's built-in commands as `$VIMRUNTIME/doc/index.txt` documents them. A mapping shows where it was made; a built-in that a mapping replaces is marked so. The file is read once per session.
- **Feature status**: `:FeatureStatus` shows every feature on this system as available, not supported here, or blocked, from `lua/config/health.lua` and each `lua/features/<purpose>/health.lua` ([how to read it](../troubleshooting.md#feature-status)).

Both load only when first used.

## Keys and commands

| Command | Does |
|---|---|
| `:KeyCheatSheet` | Every key, mapped and built-in (`<leader>sK`) |
| `:FeatureStatus` | Every feature: available, not supported here, or blocked and why |

## What it needs

Neovim's `doc/index.txt` for the built-in commands; without it only mappings are listed.

## Systems

Linux, macOS and Windows alike.
