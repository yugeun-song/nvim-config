# Troubleshooting

## Feature status

`:FeatureStatus` runs `:checkhealth config features.*` and shows every feature on this system as one of:

| Answer | Meaning | Shown as |
|---|---|---|
| available | supported here and ready, with what it uses | OK |
| not supported on this system | the system cannot do it, and why | info |
| blocked | supported, but something is missing or wrong: what, and what to do | warning |

`:checkhealth config` checks the core alone (Neovim 0.12, the plugins, `git`, `rg`, `fd`); `:checkhealth features.<category>` checks one category (`ui`, `editor`, `lang`, `lsp`, `dap`, `util`), such as `:checkhealth features.dap`.

## Where to look

| What failed | Look at |
|---|---|
| A debug session | `:DbgLog` (the last 400 messages and the tail of nvim-dap's log), `:DbgState` |
| A Mason install | `mason.log` in `stdpath("log")`; `:MasonInstall NAME` retries one held back |
| The Windows IME helper's build | `windows_ime_helper-*.log` in `stdpath("data")/nvim-config/windows_ime_helper`; delete it to retry |
| A Windows shim | `windows_ime_helper_shims.log` in `stdpath("data")/nvim-config/registered_program_shims` |
| A Visual Studio compile database | the notification names the cause; MSBuild's output is `msvc_compile_database.log` in `stdpath("state")/nvim-config` |
| A language server where it should not run | `<leader>cLl`: the attach rule that decided |
| Anything left by older versions | `:ManagedPaths` lists what an older layout left, as safe to remove |

## Caveats

- **A QEMU gdbstub takes one client**: while Neovim is attached, another `gdb` cannot connect; use the gdb console panel.
- **Source lines, stepping and locals need `-g`** (`-g -O0` for line stepping); `<leader>dF` breaks on a symbol or address without it.
- **A QEMU user-mode stub cannot be interrupted**: `<leader>dP` does nothing, and a breakpoint change waits for the next stop.
- **Early-boot arming can take tens of seconds** (direct boots, x86 UEFI with KASLR); the session sits at the reset vector meanwhile, not hung.
- **An x86 UEFI guest with KASLR needs a QEMU monitor and two of the four hardware breakpoints.**
- **Opening a Haskell project runs its code**: haskell-language-server builds it, so Template Haskell and a custom `Setup.hs` execute. Treat untrusted repositories accordingly.
- **`:MsvcCompileDb` runs a Visual Studio project's code**: MSBuild evaluates the project and what it imports. It runs unasked only for a project whose database you made once.
- **`error STL1000` in every C++ file of a Visual Studio project**: the toolset's C++ library asks for a newer clangd. `:MasonInstall clangd` while clangd is not running (before a C-family file is opened, or after `:lsp stop`): Mason removes the old one first, and Windows does not let go of a running program.
- **`cmd.exe` in `:terminal` does not find a program of the current directory**: it takes `.\name` ([programs from PATH only](features/util.md#programs-from-path-only)).
- **alive-lsp knows its own image, not your project**; the REPL is a separate SBCL (`<localleader>i` interrupts a long print).
- **An Elixir breakpoint on a line holding only a literal is never hit**, though ElixirLS reports it verified; put it on a call or a match.
- **The first Elixir debug run per Elixir and OTP version is slow**: the `elixir-ls` Mason package fetches and compiles ElixirLS.
- **No window comes forward on GNOME on Wayland**: no program may raise a window there; `scripts/open-at.lua` still opens the file.
- **The terminal background stays** inside tmux, screen, Zellij and a nested Neovim: the OSC 11 follow is skipped there.
- **The `한`/`EN` indicator needs fcitx5** on Linux; with ibus or fcitx4 the IME still returns to English.
- **The indicator stops following, or the IME stays in Hangul after Insert**: Neovim believes it has no focus. It drops a focus event that arrives while a `FocusLost` or `FocusGained` autocmd still runs, so an autocmd that waits there (`vim.wait`, `:sleep`, a blocking `system()`) loses the next one. Switching to another window and back repairs it; the autocmd belongs in `vim.schedule`.
- **No swap files**: an unsaved buffer is not recovered after a crash.
