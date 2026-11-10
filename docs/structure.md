# Structure

Where everything is, and why it is there.

## Layout

```text
nvim-config/
├── init.lua                     Windows lookups and MSVC environment, registered programs, Open Folder, running
│                                instance, terminal background, the last reset's report; then lua/config/lazy.lua
├── lazy-lock.json               plugin commits
├── lazyvim.json                 LazyVim extras (mini.files)
├── LICENSE, LICENSES/           0BSD, and the Apache-2.0 text for files taken from LazyVim (THIRD-PARTY-NOTICES)
├── .editorconfig, .gitattributes, .luarc.json, .rumdl.toml, stylua.toml
│                                indentation and line ends, lua_ls, Markdown lint, StyLua
├── lua/
│   ├── config/                  autocmds, keymaps, options, lazy (the bootstrap), health (:checkhealth config)
│   ├── plugins/                 lazy.nvim specs only, in LazyVim's categories
│   │   ├── colorscheme.lua
│   │   ├── formatting.lua       formatters that serve several languages
│   │   ├── linting.lua          linters of the languages without a file in lang/
│   │   ├── treesitter.lua       parsers of the languages without a file in lang/
│   │   ├── ui/                  statusline, dashboard, search count, keystroke display, Neovide, ANSI colours
│   │   ├── editor/              explorer, pickers, Trouble, Open Folder, reload, Korean input, key cheat sheet
│   │   ├── lang/                one file per language: c, asm, cuda, lisp, haskell, lean, python, elixir, rust,
│   │   │                        typescript, markdown
│   │   ├── lsp/                 attach rules, line diagnostics, the remaining Mason packages
│   │   ├── dap/                 core (nvim-dap, gdb, LLDB, panels), linux_kernel
│   │   └── util/                managed paths, tool paths, feature status, Discord Rich Presence
│   └── features/                the configuration's own code, in the same categories and under the same names
│       ├── ui/ editor/ lang/ lsp/ dap/ util/
│       └── <category>/health.lua   :checkhealth features.<category>
├── after/ftplugin/              lisp.lua, racket.lua, man.lua
├── after/queries/asm/           injections.scm: C in .S/.s directives
├── queries/asm/                 highlights.scm
├── colors/                      spaceduck-remix.lua
├── neovide/config.toml          Neovide's own settings, linked to its configuration directory
├── native/                      windows_ime_helper.c and its .clang-format
├── scripts/                     check_repository.lua, update_credits.lua, reset_to_fresh_clone.lua, open-at.lua,
│                                alive_lsp_over_stdio.lisp
├── tests/                       managed_paths/, windows_ime_helper/
├── docs/                        this documentation; docs/features/ has one page per category
└── .github/                     workflows/, scripts/
```

`lua/config/` holds what LazyVim loads by name (`options.lua`, `keymaps.lua`, `autocmds.lua`), the bootstrap that `init.lua` requires (`lazy.lua`), and `health.lua` (`:checkhealth config`: Neovim, plugins, `git`, `rg`, `fd`).

## Categories

The categories are LazyVim's own (its `lazyvim/plugins` and `extras` use the same names). Each has one directory of specs, one of code and one page.

| Category | What it covers | Page |
|---|---|---|
| `ui` | colorscheme, statusline, dashboard, search count, keystroke display, man pages, Neovide | [UI](features/ui.md) |
| `editor` | options, motions, explorer, pickers, formatting, linting, reload, Open Folder, opening from other programs, Korean input, key cheat sheet | [editor](features/editor.md) |
| `lang` | C, C++, assembly, CUDA, MSVC, Lisp, Racket, Haskell, Lean, Python, Elixir, Rust, TypeScript, Markdown | [languages](features/lang.md) |
| `lsp` | attach rules, line diagnostics, Mason packages | [language servers](features/lsp.md) |
| `dap` | nvim-dap, gdb, LLDB, QEMU, Linux kernels, panels | [debugging](features/dap.md) |
| `util` | where everything is kept, tool paths, `:FeatureStatus`, Discord Rich Presence, the Windows platform code | [utilities](features/util.md) |

`lua/features/util/feature_status.lua` is shared by every `health.lua`: it answers each feature as available, not supported here, or blocked ([troubleshooting](troubleshooting.md#feature-status)).

## Where a feature's code is

A spec and its code share a path: `lua/plugins/<category>/<name>.lua` has its code in `lua/features/<category>/<name>.lua`, or in `lua/features/<category>/<name>/` when it takes several files.

| Spec | Code |
|---|---|
| `plugins/ui/statusline.lua` | `features/ui/statusline.lua` |
| `plugins/editor/korean_input.lua` | `features/editor/korean_input/` (`init.lua`, `backends.lua`, `indicator.lua`) |
| `plugins/lang/c.lua` | `features/lang/c/` (indentation, `#include` gf, clangd, all `#if` branches, macro bodies, MSVC) |
| `plugins/dap/core.lua` | `features/dap/core/` (`init.lua`, `sessions/`, `panels/`) |
| `plugins/util/managed_paths.lua` | `features/util/managed_paths.lua` |

Code that no single spec owns sits in its category under its own name: `features/util/storage.lua` (the configuration's own files), `features/util/windows/` (Windows only), `features/ui/terminal_background.lua` (started by `init.lua`).

## Why this layout

- **LazyVim's categories.** A LazyVim user finds a plugin where LazyVim would put it, and a language's whole setup in one file, as LazyVim's `extras/lang/*.lua` keep it: its parsers, Mason packages, servers, formatters, linters and debugger.
- **Specs and code apart, under the same names.** lazy.nvim's `import` takes every file of a directory as a spec (and not its subdirectories): a helper module in `lua/plugins/<category>/` would be read as a spec. LazyVim itself keeps its specs in `lazyvim/plugins` and its code in `lazyvim/util`.
- **A namespace of its own.** Every module of the configuration is `features.<category>.<name>`, so none can shadow a plugin's module on the runtimepath: cscope_maps.nvim ships a top-level `cscope`, nvim-dap `dap`, nvim-lint `lint`.
- **Files named by what they do.** A file says what it does (`open_in_running_instance.lua`, `executable_lookup_cache.lua`), so the tree reads as a feature list ([naming rules](development.md#naming-and-style)).
- **Import order.** `lua/config/lazy.lua` imports `lua/plugins/*.lua`, then `ui`, `editor`, `lang`, `dap`, `util`, and `lsp` last: on Windows, Mason's install gate in `lsp/mason.lua` filters the list every other spec has added to.

## The configuration's own files

What the configuration writes for itself lives in one directory, `nvim-config`, inside each of Neovim's own: `stdpath("data")`, `stdpath("state")`, `stdpath("cache")` and `stdpath("run")`. No plugin writes there. `lua/features/util/storage.lua` lists every file with what it holds and moves a file from an older layout on first use; [managed paths](features/util.md#own-files) shows the list.

## Lazy loading

- `defaults.lazy = true` in `lua/config/lazy.lua`: every plugin this configuration adds states its trigger (`event`, `ft`, `cmd`, `keys`; a colorscheme loads on `:colorscheme`); one without a trigger would never load. LazyVim's own plugins carry theirs.
- The configuration's own features are lazy.nvim `virtual` specs (nothing installed, nothing on the runtimepath) with a trigger, so their modules load on first use: `:ManagedPaths` and `<leader>uM` load `managed_paths.lua`, `<leader>uK` the keystroke display, the first C-family buffer the C features, the first search hlslens.
- Which trigger:
  1. **At start**: what the first screen shows, what the first key needs (keys typed during startup run before `VeryLazy`), or what must see an earlier event. Example: the Korean langmap.
  2. **A precise trigger** (`ft`, `cmd`, `keys`, events such as `LazyFile`, `DiagnosticChanged`): the default, for whatever only some sessions or actions use.
  3. **`VeryLazy`**: only what every session runs unasked while neither the first screen nor the first key needs it: Discord presence, the statusline's IME marks, the language servers and gitsigns (`lua/plugins/util/after_first_screen.lua`; a C file's first screen 91 to 63 ms).
- The exception is markview.nvim (`lazy = false`): its README asks not to lazy-load it, since it defers its own work and lazy-loading slows the first preview. neov-ime.nvim also loads at start, and only under Neovide (`cond`).
- Windows-only work is behind `has("win32")` and costs Linux and macOS nothing: a Windows-only spec is not added to the list elsewhere ([Windows platform](features/util.md#windows-platform)).
