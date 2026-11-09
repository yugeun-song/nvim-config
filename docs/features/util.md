# Utilities

What the configuration keeps and where, programs registered by path, `:FeatureStatus`, Discord Rich Presence, and the code that makes Windows work as the other systems do. Specs: `lua/plugins/util/`; code: `lua/features/util/`, `scripts/reset_to_fresh_clone.lua`.

## Managed paths

Where Neovim, the plugins, Neovide and this configuration keep what they write, and the way back to a fresh clone.

### Own files

The configuration writes for itself only into `nvim-config` inside `stdpath(kind)` ([why](../structure.md#the-configurations-own-files)). `storage.lua` lists every entry; one still under its old name directly in `stdpath(kind)` moves here the first time its owner asks for it, and one that cannot move is listed as left over.

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
| state | `reset_report_unread` | the last reset's report, until a start has shown it |
| state | `reset_confirmation` | the confirmation a typed `reset` leaves for the reset |
| run, else state | `running_instances` | running Neovims with a UI, for `scripts/open-at.lua` (run: in a directory per `NVIM_APPNAME`) |
| data | `windows_ime_helper` | the Windows IME helper's builds |
| data | `registered_program_shims` | one shim per registered program |
| data | `language_server_attach_rules.json` | language server attach rules |
| data | `alive_lsp` | the Common Lisp language server and its libraries |
| cache | `executable_lookup_cache.json` | `executable()` and `exepath()` answers per PATH (Windows) |
| cache | `clangd_temporary_files` | clangd's temporary files, one directory per Neovim |

### Where everything is kept

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

### Back to a fresh clone

The reset has no key, on purpose. `:ManagedPathsReset` shows the list and asks for `reset` to be typed, quits as `:confirm qa` does, and once this Neovim (and the Neovide around it) has exited, removes every line marked `remove` through `nvim -l scripts/reset_to_fresh_clone.lua`. The next start installs the plugins, Mason's packages and the parsers again and says what was removed, or why nothing was. `:ManagedPathsReset configuration` removes only this configuration's own files.

- It refuses while another Neovim with a UI runs.
- Only `reset` typed at the prompt removes anything: keys already waiting (a mapping, a macro, typeahead) are set aside, there is no default or completion, and the answer leaves no history. The script removes only with the one-time confirmation that prompt leaves.
- A directory is renamed before it is removed, so one a running program still holds (Windows refuses the rename) stays whole rather than half gone, and is reported.
- Never removed: the configuration itself (with `lazy-lock.json`) and any Neovim directory inside it, Neovide's settings link (remove it by hand), anything outside the paths listed.

From a terminal, with every Neovim closed, `nvim -l scripts/reset_to_fresh_clone.lua` lists and asks the same. No flag skips the question, and an answer from a pipe or a file is not taken; mintty (Git Bash, MSYS2) hands programs a pipe, not a console, so use Windows Terminal there, or `:ManagedPathsReset`.

### Keys and commands

| Command | Does |
|---|---|
| `:ManagedPaths` | Where everything is kept, with sizes (`<leader>uM`) |
| `:ManagedPathsReset [configuration]` | Type `reset` to quit and remove what `:ManagedPaths` marks `remove`; with `configuration`, only this configuration's own files |

### What it needs

Nothing. Tests: [development](../development.md#stored-data-paths).

### Systems

Linux, macOS and Windows; Flatpak, Snap and AppImage layouts are recognised.

## Programs registered by path

Programs off PATH, registered by path (`lua/plugins/util/tool_paths.lua`, `lua/features/util/tool_paths/`).

`<leader>uX` (or `:ToolPath`) lists the programs this configuration runs by name (`cscope`, `ctags`, `gdb`, `lldb-dap`, `yazi`, `rg`, `fd`, `tree-sitter`, `ruff`) with the one each resolves to, and registers one by path:

- `stdpath("state")/nvim-config/registered_programs.json` keeps the choice;
- `stdpath("data")/nvim-config/registered_program_shims` holds one shim per program and is the only directory added to PATH, at its end, so nothing beside the program comes into reach and a program already on PATH still wins;
- a shim is a symbolic link; on Windows it is a copy of the [IME helper](#windows-ime-helper) that runs the program named in `NAME.shim` with the same arguments and exit code, with the program's own directory first on its PATH (so MSYS2's `cscope` finds MSYS2's `sort` for its `-q` index).

With nothing registered this costs one stat at startup. A shim or `.shim` removed by hand is made again at the next start.

On Windows a `.shim` must name an `.exe` or `.com` on a local disk, absolute or relative to the shim's own directory. Drive-relative, rooted, device and network paths, alternate data streams, another shim and the shim itself are refused (a shim naming a shim could loop). A shim runs only with Neovim among its nearest ancestors (`:terminal` included), and its program runs in a job that ends with the shim. A failure goes to its stderr and to `windows_ime_helper_shims.log` beside it, which Neovim watches and shows at once.

On Windows the picker also reads what the system records, on request only (`windows_discovery.lua`, one PowerShell run): the machine and user PATH in the registry (programs installed after this Neovim started; one pick adds them to the session), App Paths, the install locations of installed programs with their usual bin directories, Visual Studio's LLVM tools through vswhere, and the winget, Scoop, Chocolatey and Cargo directories their variables name. The result is kept in `stdpath("state")/nvim-config/windows_program_discovery.json`; nothing is registered until picked.

The picker also turns the [MSVC environment](lang.md#msvc-toolchain) off and on.

### Keys and commands

| Command | Does |
|---|---|
| `:ToolPath` | Pick a program and register it (`<leader>uX`) |
| `:ToolPath NAME` | Ask for NAME's path |
| `:ToolPath NAME PATH` | Register NAME as PATH (a relative PATH is taken from the current directory) |
| `:ToolPath! NAME` | Forget NAME |

### What it needs

Shims need nothing more on Linux and macOS; on Windows they need the [IME helper](#windows-ime-helper).

### Systems

| Part | Linux | macOS | Windows |
|---|---|---|---|
| Programs registered by path | yes | yes | yes |
| Discovery from the system's records | no | no | yes |

## Feature status

`:FeatureStatus` shows every feature on this system as available, not supported here, or blocked, from `lua/config/health.lua` and each `lua/features/<category>/health.lua` ([how to read it](../troubleshooting.md#feature-status)). It loads only when first used.

### Systems

Linux, macOS and Windows alike.

## Discord Rich Presence

The editor shown in Discord (`lua/plugins/util/discord_rich_presence.lua`, `lua/features/util/discord_rich_presence.lua`).

### What it does

Rich Presence over Discord's IPC socket (a named pipe on Windows), written from the public protocol, with no plugin. On by default from `VeryLazy`, it shows "Editing in Neovim" and the elapsed time; no file or workspace names. It finds the desktop client's socket, and those of its Snap and Flatpak builds and of Vesktop's Flatpak.

It borrows the public application ID and `neovim` art of [presence.nvim](https://github.com/andweeb/presence.nvim). `vim.g.discord_rich_presence_client_id`, set before the first screen, uses an application of one's own, and `vim.g.discord_rich_presence_image` names its art.

### Keys and commands

| Command | Does |
|---|---|
| `:DiscordRpcToggle` | Turn it on or off (`<leader>uP`) |
| `:DiscordRpcStatus` | Say whether it runs and its connection state |

### What it needs

The Discord desktop client (or Vesktop), running.

### Systems

Linux, macOS and Windows. Under WSL the Windows client's pipe is not reachable.

## Windows platform

What Windows lacks and Linux has elsewhere: an IME tool, a Caps Lock LED, a window raise, symbolic links, fast program lookups. Everything here sits behind `has("win32")`; Linux and macOS run none of it. Code: `lua/features/util/windows/`, `native/windows_ime_helper.c`. No specs: `init.lua` and the features that need it load it.

### Windows IME helper

`native/windows_ime_helper.c`, kept in this repository and built at the first start (and after the source changes) in the background into `stdpath("data")/nvim-config/windows_ime_helper`; nothing is downloaded.

| Command | Does |
|---|---|
| `ime-english` | Turn the foreground window's IME to its alphanumeric mode, keeping the keyboard layout (as `fcitx5-remote -c` does) |
| `input-state` | Print `<caps><ime>` once (`1` = on, or native script) |
| `watch-input-state PID [MS]` | Print `<caps><ime>` on each change until PID exits, polling every MS (100 by default); stdin `e`, `p`, `r` = ime-english, pause, resume |
| `raise-window PID` | Raise the window of PID, or of its nearest ancestor that has one |
| `version` | Print the compiler and architecture; the build runs it to prove every import loads |

Copied as `NAME.exe` beside a `NAME.shim`, it runs the program that file names instead ([shims](#programs-registered-by-path)). It serves the [IME switch and indicators](editor.md#korean-input), the [window raise](editor.md#opening-from-other-programs) and the shims.

- **Build.** x86_64 Windows only, by Visual Studio's `cl` (on PATH through the [MSVC environment](lang.md#msvc-toolchain)) or clang targeting MSVC; the preprocessor stops any other target or compiler (Linux, macOS, MinGW, 32-bit, ARM64). Warnings fail the build, the linker's too; the C runtime is linked in, so the program loads only the system's DLLs. A build that does not answer `version` exactly is discarded and the next compiler tried; the compilers' output is kept in `windows_ime_helper-*.log` beside the builds (delete it to retry).
- **Only for Neovim.** It runs only as Neovim's child (its parent must be `nvim.exe`, checked against reused process ids; a shim's may be a few levels up, for `:terminal`) and ends with Neovim: the watcher waits on Neovim's process and its stdin.
- **No keystrokes.** It reads only Caps Lock and the IME's mode, polled rather than hooked, since a keyboard hook would see every key; even that state is wiped once used.
- **Failures.** Exit codes: 0 done, 1 failed, 2 usage, 3 a protocol violation on stdin, 4 not started by Neovim, 127 a shim that cannot run its program. Neovim shows each failure once and lists them in `:checkhealth features.editor`.

Style and tests: [development](../development.md#windows-ime-helper).

### Faster on Windows

- **Program lookups** (`executable_lookup_cache.lua`): Windows' `executable()` and `exepath()` try every PATHEXT extension in every PATH directory, about 10 ms a name with forty directories. Lua callers, `vim.system()` and the plugins included, get the answer from `stdpath("cache")/nvim-config/executable_lookup_cache.json`, kept per PATH with each directory's mtime and checked again every two seconds, so a program installed meanwhile is seen. A changed directory drops only the answers it can affect.
- **matchit and netrw** load before lazy.nvim fills the runtimepath: `:packadd` resolves every entry, about 20 ms more apiece on a full one.
- **lazy.nvim's update checks** start git once per plugin, and Windows holds the editor about 5 ms per process; they wait until no key has come for 5 s outside a terminal, or until Neovim loses focus.

Elsewhere on Windows: [MSVC environment, compile databases, `--query-driver`](lang.md#msvc-toolchain), [LLDB beside gdb](dap.md#choosing-gdb-and-lldb), [Mason's install gate](lsp.md#mason-packages), [program discovery](#programs-registered-by-path).

### Keys and commands

None of its own. `:checkhealth features.util` shows whether the lookup memory is installed and the helper is built.

### What it needs

Visual Studio (or its Build Tools) with the MSVC tools, or clang targeting MSVC, to build the helper.

### Systems

Windows (x86_64) only. On Linux and macOS, `:FeatureStatus` reports it as not supported.
