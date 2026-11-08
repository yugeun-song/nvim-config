# Windows platform

What Windows lacks and Linux has elsewhere: an IME tool, a Caps Lock LED, a window raise, symbolic links, fast program lookups. Everything here sits behind `has("win32")`; Linux and macOS run none of it. Code: `lua/features/windows_platform/`, `native/windows_ime_helper.c`, `lua/config/lazy.lua`. No specs: `init.lua` and the features that need it load it.

## Windows IME helper

`native/windows_ime_helper.c`, kept in this repository and built at the first start (and after the source changes) in the background into `stdpath("data")/nvim-config/windows_ime_helper`; nothing is downloaded.

| Command | Does |
|---|---|
| `ime-english` | Turn the foreground window's IME to its alphanumeric mode, keeping the keyboard layout (as `fcitx5-remote -c` does) |
| `input-state` | Print `<caps><ime>` once (`1` = on, or native script) |
| `watch-input-state PID [MS]` | Print `<caps><ime>` on each change until PID exits, polling every MS (100 by default); stdin `e`, `p`, `r` = ime-english, pause, resume |
| `raise-window PID` | Raise the window of PID, or of its nearest ancestor that has one |
| `version` | Print the compiler and architecture; the build runs it to prove every import loads |

Copied as `NAME.exe` beside a `NAME.shim`, it runs the program that file names instead ([shims](external_programs.md#programs-registered-by-path)). It serves the [IME switch and indicators](input_method.md), the [window raise](editing.md#opening-from-other-programs) and the shims.

- **Build.** x86_64 Windows only, by Visual Studio's `cl` (on PATH through the [MSVC environment](languages.md#msvc-toolchain)) or clang targeting MSVC; the preprocessor stops any other target or compiler (Linux, macOS, MinGW, 32-bit, ARM64). Warnings fail the build, the linker's too; the C runtime is linked in, so the program loads only the system's DLLs. A build that does not answer `version` exactly is discarded and the next compiler tried; the compilers' output is kept in `windows_ime_helper-*.log` beside the builds (delete it to retry).
- **Only for Neovim.** It runs only as Neovim's child (its parent must be `nvim.exe`, checked against reused process ids; a shim's may be a few levels up, for `:terminal`) and ends with Neovim: the watcher waits on Neovim's process and its stdin.
- **No keystrokes.** It reads only Caps Lock and the IME's mode, polled rather than hooked, since a keyboard hook would see every key; even that state is wiped once used.
- **Failures.** Exit codes: 0 done, 1 failed, 2 usage, 3 a protocol violation on stdin, 4 not started by Neovim, 127 a shim that cannot run its program. Neovim shows each failure once and lists them in `:checkhealth features.input_method`.

Style and tests: [development](../development.md#windows-ime-helper).

## Faster on Windows

- **Program lookups** (`executable_lookup_cache.lua`): Windows' `executable()` and `exepath()` try every PATHEXT extension in every PATH directory, about 10 ms a name with forty directories. Lua callers, `vim.system()` and the plugins included, get the answer from `stdpath("cache")/nvim-config/executable_lookup_cache.json`, kept per PATH with each directory's mtime and checked again every two seconds, so a program installed meanwhile is seen. A changed directory drops only the answers it can affect.
- **matchit and netrw** load before lazy.nvim fills the runtimepath: `:packadd` resolves every entry, about 20 ms more apiece on a full one.
- **lazy.nvim's update checks** start git once per plugin, and Windows holds the editor about 5 ms per process; they wait until no key has come for 5 s outside a terminal, or until Neovim loses focus.
- **cscope_maps** loads on its commands and keys, or for a tree with a `cscope.out`, instead of with every file.

Elsewhere on Windows: [MSVC environment, compile databases, `--query-driver`](languages.md#msvc-toolchain), [LLDB beside gdb](debugging.md#choosing-gdb-and-lldb), [Mason's install gate](external_programs.md#mason-packages), [program discovery](external_programs.md#programs-registered-by-path).

## Keys and commands

None of its own. `:checkhealth features.windows_platform` shows whether the lookup memory is installed and the helper is built.

## What it needs

Visual Studio (or its Build Tools) with the MSVC tools, or clang targeting MSVC, to build the helper.

## Systems

Windows (x86_64) only. On Linux and macOS, `:FeatureStatus` reports it as not supported.
