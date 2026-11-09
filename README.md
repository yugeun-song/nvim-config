# nvim-config

A [LazyVim](https://www.lazyvim.org/)-based Neovim configuration for Linux kernel and C development: a debugger on GDB's own DAP, language server rules per path, Korean input-method integration, a keystroke display, a hand-written colorscheme and a Neovide profile. Heavy yet light: plugins and features load when first needed, and Windows support costs Linux and macOS nothing.

## Highlights

- **C and the kernel**: clangd, cscope and `tags` tuned for big trees; indentation from `.editorconfig` or `.clang-format`, no autoformat; every `#if` branch on request; assembly, linker scripts and device trees highlighted; CUDA and Visual Studio projects in clangd. [Languages](docs/features/lang.md)
- **Debugger on `gdb -i dap`** for programs, QEMU user mode and Linux kernels behind a QEMU gdbstub, with registers, memory, disassembly and control-flow panels; LLDB on macOS and Windows; Python, Rust, JS/TS and Elixir through their own adapters. [Debugging](docs/features/dap.md)
- **Attach rules** turn a language server off per file or directory. [Language servers](docs/features/lsp.md#attach-rules)
- **Korean input**: English on leaving Insert mode, `한`/`EN` and Caps Lock in the statusline, a Dubeolsik `langmap`. [Korean input](docs/features/editor.md#korean-input)
- **Open Folder** in yazi with sessions, and files sent into the running Neovim from other programs. [Editor](docs/features/editor.md#editing)
- **`spaceduck-remix`**, a dashboard with the system's logo, the ChKeys keystroke display, a Neovide profile. [UI](docs/features/ui.md)
- **Self-describing**: `<leader>sK` lists every key; `:FeatureStatus` shows every feature as available, not supported here, or blocked and why; `:ManagedPaths` shows where everything is kept. [Key cheat sheet](docs/features/editor.md#key-cheat-sheet), [utilities](docs/features/util.md)

## Supported systems

| System | Support |
|---|---|
| Arch Linux (x86_64, Hyprland, kitty or Neovide, fcitx5) | Full: the system it is built on |
| Debian, Ubuntu, Fedora, openSUSE and other Linux | Full; package names and gdb versions differ |
| macOS | Partly: C and C++ debug through LLDB; no QEMU user mode or kernel debugging |
| Windows (x86_64) | Partly: no man page highlighting, QEMU user mode or kernel debugging |
| WSL | As Linux, with the IME switch through `im-select.exe` |
| Neovim 0.11 or older | Unsupported |

What each system needs: [installation](docs/installation.md).

## Quick install

Neovim 0.12 or later, `git`, the `tree-sitter` CLI, a C compiler, `curl` and `tar`; `rg`, `fd` and a Nerd Font are recommended ([all requirements](docs/installation.md#requirements)).

```sh
mv ~/.config/nvim ~/.config/nvim.bak 2>/dev/null
git clone https://github.com/yugeun-song/nvim-config.git ~/.config/nvim
nvim
```

On Windows:

```powershell
git clone https://github.com/yugeun-song/nvim-config.git $env:LOCALAPPDATA\nvim
nvim
```

The first start installs the plugins, parsers and Mason packages; restart once, then run `:FeatureStatus` ([first start](docs/installation.md#first-start)).

## Documentation

| Document | Contents |
|---|---|
| [installation](docs/installation.md) | requirements per feature and per system, first start, Neovide |
| [features](docs/structure.md#categories) | one page per LazyVim category (ui, editor, lang, lsp, dap, util): what it does, keys and commands, what it needs, per-system support |
| [keymaps](docs/keymaps.md) | every key this configuration adds |
| [structure](docs/structure.md) | layout, why it is laid out so, where its files are kept, lazy loading |
| [development](docs/development.md) | rules, `scripts/check_repository.lua`, tests, CI |
| [troubleshooting](docs/troubleshooting.md) | `:FeatureStatus`, logs, caveats |
| [credits](docs/credits.md) | code taken in, plugins, Mason packages and programs, with their licenses |

## License

0BSD ([`LICENSE`](LICENSE)). Files taken from other projects keep their own licenses ([`THIRD-PARTY-NOTICES`](THIRD-PARTY-NOTICES)); [credits](docs/credits.md) lists them.
