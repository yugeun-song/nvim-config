# Maintenance

Where Neovim, the plugins, Neovide and this configuration keep what they write, and the way back to a fresh clone. Spec: `lua/plugins/maintenance/stored_data_paths.lua`; code: `lua/features/maintenance/` (`local_storage.lua`, `stored_data_paths.lua`), `scripts/reset_to_fresh_clone.lua`.

## Own files

The configuration writes for itself only into `nvim-config` inside `stdpath(kind)` ([why](../structure.md#the-configurations-own-files)). `local_storage.lua` lists every entry; one still under its old name directly in `stdpath(kind)` moves here the first time its owner asks for it, and one that cannot move is listed as left over.

| Kind | Entry | Holds |
|---|---|---|
| state | `registered_programs.json` | programs registered by path |
| state | `windows_program_discovery.json` | programs `<leader>uX` found (Windows) |
| state | `mason_install_failures.json` | Mason installs held back after a failure |
| state | `msvc_developer_environment.json` | the MSVC environment VsDevCmd sets (Windows) |
| state | `msvc_compile_databases.json` | databases `:MsvcCompileDb` wrote (Windows) |
| state | `all_ifdef_branches` | the all-`#if`-branches view, on or off |
| state | `open_folder_history` | folders opened (Projects) |
| state | `colorscheme_choice` | the default colorscheme confirmed in `<leader>uC` |
| state | `reset_report.txt` | what the last reset removed |
| state | `reset_confirmation` | the confirmation a typed `reset` leaves for the reset |
| run, else state | `running_instances` | running Neovims with a UI, for `scripts/open-at.lua` |
| data | `windows_ime_helper` | the Windows IME helper's builds |
| data | `registered_program_shims` | one shim per registered program |
| data | `language_server_attach_rules.json` | language server attach rules |
| data | `alive_lsp` | the Common Lisp language server and its libraries |
| cache | `executable_lookup_cache.json` | `executable()` and `exepath()` answers per PATH (Windows) |
| cache | `clangd_temporary_files` | clangd's temporary files, one directory per Neovim |

## Where everything is kept

`<leader>uM` (or `:ManagedPaths`) lists where everything is kept, read from Neovim and the system each time rather than written down:

- Neovim's own directories (`stdpath()` config, data, state, log and cache), with what each entry holds and its size, measured in the background;
- Neovide's settings (`$XDG_CONFIG_HOME/neovide`, else `~/.config/neovide`, on Linux and macOS; `%APPDATA%\neovide`; or the file `NEOVIDE_CONFIG` names) and the window state it remembers;
- the `compile_commands.json` files `:MsvcCompileDb` wrote;
- what Neovim puts on PATH, inside the running Neovim only: Mason's `bin`, the shims, the MSVC environment. Nothing else is written: not the system or user PATH, the registry or a shell profile.

Its first lines say what decided that layout: `NVIM_APPNAME`, each `XDG_*_HOME` that is set (Neovim reads them on Windows too), a Flatpak sandbox (`FLATPAK_ID`, `/.flatpak-info`), a Snap, an AppImage, or the defaults. `<CR>` opens a line's path, `y` copies it.

| Directory | Linux and macOS default | Windows default |
|---|---|---|
| config | `~/.config/nvim` | `%LOCALAPPDATA%\nvim` |
| data | `~/.local/share/nvim` | `%LOCALAPPDATA%\nvim-data` |
| state | `~/.local/state/nvim` | `%LOCALAPPDATA%\nvim-data` |
| cache | `~/.cache/nvim` | `%TEMP%\nvim` |

## Back to a fresh clone

The reset has no key, on purpose. `:ManagedPathsReset` shows the list and asks for `reset` to be typed, quits as `:confirm qa` does, and once this Neovim (and the Neovide around it) has exited, removes every line marked `remove` through `nvim -l scripts/reset_to_fresh_clone.lua`. The next start installs the plugins, Mason's packages and the parsers again and says what was removed. `:ManagedPathsReset configuration` removes only this configuration's own files.

- It refuses while another Neovim with a UI runs.
- Only `reset` typed at the prompt removes anything: keys already waiting (a mapping, a macro, typeahead) are set aside, there is no default or completion, and the answer leaves no history. The script removes only with the one-time confirmation that prompt leaves.
- A directory is renamed before it is removed, so one a running program still holds (Windows refuses the rename) stays whole rather than half gone, and is reported.
- Never removed: the configuration itself (with `lazy-lock.json`) and any Neovim directory inside it, Neovide's settings link (remove it by hand), anything outside the paths listed.

From a terminal, with every Neovim closed, `nvim -l scripts/reset_to_fresh_clone.lua` lists and asks the same. No flag skips the question, and an answer from a pipe or a file is not taken.

## Keys and commands

| Command | Does |
|---|---|
| `:ManagedPaths` | Where everything is kept, with sizes (`<leader>uM`) |
| `:ManagedPathsReset [configuration]` | Type `reset` to quit and remove what `:ManagedPaths` marks `remove`; with `configuration`, only this configuration's own files |

## What it needs

Nothing. Tests: [development](../development.md#stored-data-paths).

## Systems

Linux, macOS and Windows; Flatpak, Snap and AppImage layouts are recognised.
