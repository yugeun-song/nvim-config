# Installation

What to install, per feature and per system. The clone itself is in the [README](../README.md#quick-install).

## Requirements

[Dependencies](dependencies.md) lists everything by level (required, recommended, per feature, development) and by who installs it (you, lazy.nvim, Mason, nvim-treesitter). Required: Neovim 0.12 or later, `git`, the `tree-sitter` CLI (0.26.1 or later), a C compiler, `curl`, `tar`, and network access on the first start. `:FeatureStatus` lists every feature as available, not supported here, or blocked with what is missing ([troubleshooting](troubleshooting.md#feature-status)).

For the kernel workflow, generate the indexes in the source tree: `make C=2 compile_commands.json` (or `scripts/clang-tools/gen_compile_commands.py`), `make cscope`, `make tags`.

## First start

The first start installs lazy.nvim, the plugins, the parsers and the Mason packages (into `stdpath("data")`: `~/.local/share/nvim` on Linux and macOS, `%LOCALAPPDATA%\nvim-data` on Windows). Check with `:Lazy` and `:LazyHealth`, restart once, then run `:FeatureStatus`. Update the plugins with `:Lazy update` (commits are recorded in `lazy-lock.json`) and the configuration with `git pull`.

To try it beside another configuration, clone it as another `NVIM_APPNAME`:

```sh
git clone https://github.com/yugeun-song/nvim-config.git ~/.config/test-nvim
NVIM_APPNAME=test-nvim nvim
```

Neovide reads its own settings; link the ones here (on Windows a junction needs no administrator):

```sh
ln -s ~/.config/nvim/neovide ~/.config/neovide
```

```powershell
New-Item -ItemType Junction -Path $env:APPDATA\neovide -Target $env:LOCALAPPDATA\nvim\neovide
```

## Arch Linux

The system it is built on: x86_64 with Hyprland, kitty or Neovide, and fcitx5. Everything works. gdb comes from `pacman -S gdb`; a foreign target's gdb is `<triple>-gdb` (`aarch64-linux-gnu-gdb`, say) or `gdb-multiarch`, with the sysroot in `/usr/<triple>`.

## Debian and Ubuntu

- `fd` is installed as `fdfind`; both names are found.
- A gdb older than 14 has no DAP: `apt install gdb` must bring 14 or later. Foreign targets: `apt install gdb-multiarch`.
- If the distribution's Neovim is older than 0.12, use the official [release build](https://github.com/neovim/neovim/releases).

## Fedora

gdb comes from `dnf install gdb`. A cross sysroot is found in `/usr/<triple>/sys-root` as well as `/usr/<triple>`.

## openSUSE

gdb comes from `zypper install gdb`. Leap's gdb has no riscv64 target.

## Other Linux systems

| System | gdb |
|---|---|
| Alpine | `apk add gdb`; foreign targets `apk add gdb-multiarch` |
| Void | `xbps-install gdb` |
| NixOS | add `pkgs.gdb` |

A Mason package with no build for the machine is reported as not supported; the distribution's own program on PATH serves instead. Desktops other than Hyprland raise windows through their own tool ([editing](features/editor.md#opening-from-other-programs)).

## macOS

- Neovim: `brew install neovim`.
- IME: `macism`, `im-select` or `issw`; Caps Lock and the window raise go through `osascript`.
- C and C++ debug through LLDB: `xcode-select --install` brings `lldb-dap` (Xcode 16 tools), or `:MasonInstall codelldb`. gdb cannot debug programs on Apple silicon; on Intel, `brew install gdb` and codesign it.
- QEMU user mode and Linux kernels are Linux only.

## Windows

- The configuration is `%LOCALAPPDATA%\nvim`; data, state and logs are `%LOCALAPPDATA%\nvim-data`; the cache is `%TEMP%\nvim`.
- Visual Studio 2026 (or its Build Tools) with the C++ tools builds the [IME helper](features/util.md#windows-ime-helper), sets the [MSVC environment](features/lang.md#msvc-toolchain) and writes compile databases. clang targeting MSVC also builds the helper; without either, the IME switch uses `im-select.exe`.
- Visual Studio's C++ library refuses a clangd older than it was written for, and Mason does not update what it installed: after a Visual Studio update, `:MasonInstall clangd` before opening a C-family file (Mason cannot replace a clangd that runs). `:MsvcCompileDb` says so when it applies.
- A program named without a directory starts from PATH only, never from the current directory ([why](features/util.md#programs-from-path-only)); in `:terminal`'s `cmd.exe`, a program there takes `.\name`.
- gdb: MSYS2's `pacman -S mingw-w64-ucrt-x86_64-gdb` (`mingw-w64-ucrt-x86_64-gdb-multiarch` for foreign targets), found under `C:\msys64` when not on PATH.
- cscope has no native build: register one by path with `<leader>uX`, such as MSYS2's ([external programs](features/util.md#programs-registered-by-path)).
- GHCup installs to `C:\ghcup\bin`, which joins PATH with the first Haskell buffer.
- Not available: `:Man` highlighting, QEMU user mode, Linux kernels.
- `nvim.exe` started outside a terminal opens in the console host with its own font: make Windows Terminal the default terminal application (Settings > System > For developers). `"font": { "size": 11, "cellWidth": "0.9ch" }` matches kitty's cells. Windows Terminal binds Ctrl+C and Ctrl+V to copy and paste; bind those actions to Ctrl+Shift+C and Ctrl+Shift+V, as kitty does, so `<C-v>` and `<C-c>` reach Neovim.

## WSL and SSH

- WSL works as Linux, with the IME switch through `im-select.exe`.
- Over SSH, the terminal background follow reaches the local terminal; the IME switch and marks are off, and the window raise acts on the remote host.
