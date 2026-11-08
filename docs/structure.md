# Structure

Where everything is, and why it is there.

## Layout

```text
nvim-config/
├── init.lua                 Windows lookups and MSVC environment, registered programs, Open Folder, running
│                            instance, terminal background; then lua/config/lazy.lua
├── lazy-lock.json           plugin commits
├── lazyvim.json             LazyVim extras (mini.files)
├── LICENSE, LICENSES/       0BSD, and the Apache-2.0 text for files taken from LazyVim (THIRD-PARTY-NOTICES)
├── .editorconfig, .gitattributes, .luarc.json, .rumdl.toml, stylua.toml
│                            indentation and line ends, lua_ls, Markdown lint, StyLua
├── lua/
│   ├── config/              LazyVim's fixed entry points and the core health check
│   ├── plugins/<purpose>/   lazy.nvim specs only
│   └── features/<purpose>/  the configuration's own code, with a health.lua per purpose
├── after/ftplugin/          lisp.lua, racket.lua, man.lua
├── after/queries/asm/       injections.scm: C in .S/.s directives
├── queries/asm/             highlights.scm
├── colors/                  spaceduck-remix.lua
├── neovide/config.toml      Neovide's own settings, linked to its configuration directory
├── native/                  windows_ime_helper.c and its .clang-format
├── scripts/                 check_repository.lua, update_credits.lua, reset_to_fresh_clone.lua, open-at.lua,
│                            alive_lsp_over_stdio.lisp
├── tests/                   stored_data_paths/, windows_ime_helper/
├── docs/                    this documentation
└── .github/                 workflows/tests.yml, scripts/report_failure_as_annotation.sh
```

`lua/config/` holds what LazyVim loads by name (`options.lua`, `keymaps.lua`, `autocmds.lua`), the bootstrap that `init.lua` requires (`lazy.lua`), and `health.lua` (`:checkhealth config`: Neovim, plugins, `git`, `rg`, `fd`).

## Purposes

Each purpose has one directory under `lua/plugins/` (specs) and one under `lua/features/` (code), and one document.

| Purpose | What it covers | Document |
|---|---|---|
| `appearance` | colorscheme, statusline, dashboard, keystroke display, man pages, Neovide | [appearance](features/appearance.md) |
| `editing` | motions, explorer, formatting, linting, reload, Open Folder, opening from other programs | [editing](features/editing.md) |
| `help` | key cheat sheet, `:FeatureStatus` | [help](features/help.md) |
| `input_method` | Korean `langmap`, IME switch, `한`/`EN` and Caps Lock indicators | [input method](features/input_method.md) |
| `languages` | C, C++, CUDA, assembly, MSVC, Lisp, Racket, Haskell, Lean, Python, Elixir, parsers | [languages](features/languages.md) |
| `language_servers` | attach rules per file or directory | [language servers](features/language_servers.md) |
| `debugging` | nvim-dap, gdb, LLDB, QEMU, Linux kernels, panels | [debugging](features/debugging.md) |
| `external_programs` | Mason packages, programs registered by path | [external programs](features/external_programs.md) |
| `windows_platform` | Windows only: the IME helper, `executable()` memory (no specs) | [Windows platform](features/windows_platform.md) |
| `maintenance` | where everything is kept, the reset | [maintenance](features/maintenance.md) |
| `integrations` | Discord Rich Presence | [integrations](features/integrations.md) |

`lua/features/feature_status.lua` is shared by every `health.lua`: it answers each feature as available, not supported here, or blocked ([troubleshooting](troubleshooting.md#feature-status)).

## Why this layout

- **Specs and code apart.** lazy.nvim's `import` takes every file of a directory as a spec (and not its subdirectories): a helper module in `lua/plugins/` would be read as a spec. `lua/config/lazy.lua` imports one directory per purpose; the code lives in `lua/features/`.
- **As LazyVim does.** LazyVim itself keeps its specs in `lazyvim/plugins` and its code in `lazyvim/util`.
- **A namespace of its own.** Every module of the configuration is `features.<purpose>.<name>`, so none can shadow a plugin's module on the runtimepath: cscope_maps.nvim ships a top-level `cscope`, nvim-dap `dap`, nvim-lint `lint`.
- **Files named by purpose.** A file says what it does (`open_in_running_instance.lua`, `executable_lookup_cache.lua`), so the tree reads as a feature list ([naming rules](development.md#naming-and-style)).

## The configuration's own files

What the configuration writes for itself lives in one directory, `nvim-config`, inside each of Neovim's own: `stdpath("data")`, `stdpath("state")`, `stdpath("cache")` and `stdpath("run")`. No plugin writes there. `lua/features/maintenance/local_storage.lua` lists every file with what it holds and moves a file from an older layout on first use; [maintenance](features/maintenance.md#own-files) shows the list.

## Lazy loading

- `defaults.lazy = true` in `lua/config/lazy.lua`: every plugin this configuration adds states its trigger (`event`, `ft`, `cmd`, `keys`; a colorscheme loads on `:colorscheme`); one without a trigger would never load. LazyVim's own plugins carry theirs.
- The configuration's own features are lazy.nvim `virtual` specs (nothing installed, nothing on the runtimepath) with a trigger, so their modules load on first use: `:ManagedPaths` and `<leader>uM` load `stored_data_paths.lua`, `VeryLazy` loads the IME switch.
- The exception is markview.nvim (`lazy = false`): its README asks not to lazy-load it, since it defers its own work and lazy-loading slows the first preview. neov-ime.nvim also loads at start, and only under Neovide (`cond`).
- Windows-only work is behind `has("win32")` and costs Linux and macOS nothing: a Windows-only spec returns `{}` elsewhere ([Windows platform](features/windows_platform.md)).
