# Utilities

What the configuration keeps and where, programs registered by path, `:FeatureStatus`, Discord Rich Presence, and the code that makes Windows work as the other systems do. Specs: `lua/plugins/util/`; code: `lua/features/util/`, `scripts/reset_to_fresh_clone.lua`.

## Managed paths

Where Neovim, the plugins, Neovide and this configuration keep what they write, and the way back to a fresh clone.

### Own files

The configuration writes for itself only into `nvim-config` inside `stdpath(kind)` ([why](../structure.md#the-configurations-own-files)). `storage.lua` lists every entry. One still under its old name in `stdpath(kind)` moves here on first use; one that cannot move is listed as left over. `nvim-focus` in `stdpath("run")`, shared by every `NVIM_APPNAME`, is left alone and ends with the session.

| Kind | Entry | Holds |
|---|---|---|
| state | `registered_programs.json` | programs registered by path |
| state | `windows_program_discovery.json` | programs `<leader>uX` found (Windows) |
| state | `mason_install_failures.json` | Mason installs held back after a failure |
| state | `msvc_developer_environment.json` | the MSVC environment VsDevCmd sets (Windows) |
| state | `msvc_compile_databases.json` | databases `:MsvcCompileDb` wrote (Windows) |
| state | `msvc_compile_database.log` | MSBuild's output of the last `:MsvcCompileDb` run (Windows) |
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

Nothing. Tests: [development](../development.md#managed-paths).

### Systems

Linux, macOS and Windows; Flatpak, Snap and AppImage layouts are recognised.

## Programs registered by path

Programs off PATH, registered by path (`lua/plugins/util/tool_paths.lua`, `lua/features/util/tool_paths/`).

`<leader>uX` (or `:ToolPath`) lists the programs this configuration runs by name (`cscope`, `ctags`, `gdb`, `lldb-dap`, `yazi`, `rg`, `fd`, `tree-sitter`, `ruff`) with the one each resolves to, and registers one by path:

- `stdpath("state")/nvim-config/registered_programs.json` keeps the choice;
- `stdpath("data")/nvim-config/registered_program_shims` holds one shim per program and is the only directory added to PATH, at its end, so nothing beside the program comes into reach and a program already on PATH still wins;
- a shim is a symbolic link; on Windows it is a copy of the [IME helper](#windows-ime-helper) that runs the program named in `NAME.shim` with the same arguments and exit code, with the program's own directory first on its PATH (so MSYS2's `cscope` finds MSYS2's `sort` for its `-q` index).

With nothing registered this costs one stat at startup. A shim or `.shim` removed by hand is made again at the next start. An unreadable `registered_programs.json` is never overwritten: nothing is registered or put on PATH until it is fixed or removed (`:checkhealth features.util` says why).

On Windows a `.shim` must name an `.exe` or `.com` on a local disk, absolute or relative to the shim's own directory. Drive-relative, rooted, device and network paths, alternate data streams, a directory holding `;` (on PATH it would split, leaving a relative entry), another shim and the shim itself are refused (a shim naming a shim could loop). A program in a drive's root gets `C:\` on its PATH, never the drive-relative `C:`. Registration and `:checkhealth features.util` refuse the same, with the same reasons; only a CD drive is left to the shim. A shim runs only with Neovim among its nearest ancestors (`:terminal` included), and its program runs in a job that ends with the shim. A failure goes to its stderr and to `windows_ime_helper_shims.log` beside it, which Neovim watches and shows at once.

On Windows the picker also reads what the system records, on request only (`windows_discovery.lua`, one PowerShell run): the machine and user PATH in the registry (programs installed after this Neovim started; one pick adds them to the session), App Paths, the install locations of installed programs with their usual bin directories, Visual Studio's LLVM tools through vswhere, and the winget, Scoop, Chocolatey and Cargo directories their variables name. Network locations (`\\server\share`) are skipped: an unanswering one would hold the editor. The result is kept in `stdpath("state")/nvim-config/windows_program_discovery.json`; nothing is registered until picked.

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

Rich Presence over Discord's IPC socket (a named pipe on Windows), written from the public protocol, with no plugin. On by default from `VeryLazy` (a headless Neovim, from its first UI), it shows "Editing in Neovim" and the elapsed time; no file or workspace names. It finds the desktop client's socket, and those of its Snap and Flatpak builds and of Vesktop's Flatpak, and uses one only when this user's process serves it: another account can create the name while Discord is not running.

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

`native/windows_ime_helper.c`, kept in this repository and built at the first start (and after the source changes) in the background into `stdpath("data")/nvim-config/windows_ime_helper`; nothing is downloaded. What it serves begins as the build lands, without a restart.

| Command | Does |
|---|---|
| `ime-english` | Turn the foreground window's IME to its alphanumeric mode, keeping the keyboard layout (as `fcitx5-remote -c` does) |
| `input-state` | Print `<caps><ime>` once (`1` = on, or native script) |
| `watch-input-state PID [MS]` | Print `<caps><ime>` on each change until PID exits, polling every MS (100 by default); stdin `e`, `p`, `r` = ime-english, pause, resume |
| `raise-window PID` | Raise the window of the Neovim PID: its terminal's, or that of its nearest ancestor that has one (never the desktop's) |
| `version` | Print the compiler and architecture; the build runs it to prove every import loads |

Copied as `NAME.exe` beside a `NAME.shim`, it runs the program that file names instead ([shims](#programs-registered-by-path)). It serves the [IME switch and indicators](editor.md#korean-input), the [window raise](editor.md#opening-from-other-programs) and the shims.

- **Build.** x86_64 Windows only, by Visual Studio's `cl`, run by its full path in the toolset the [MSVC environment](lang.md#msvc-toolchain) names (PATH may list folders other users can write before it), or clang targeting MSVC; the preprocessor stops any other target or compiler (Linux, macOS, MinGW, 32-bit, ARM64). `CL`, `_CL_`, `LINK` and `_LINK_` are emptied for the build. Warnings fail the build, the linker's too; the C runtime is linked in, so the program loads only the system's DLLs. A build is named after a hash of the source and of every compiler's arguments, so a changed flag builds anew. A build that does not answer `version` exactly is discarded and the next compiler tried; the compilers' output is kept in `windows_ime_helper-*.log` beside the builds. A failed build is said at every start, the previous build runs meanwhile when there is one, and it is tried again once the compilers, PATH, INCLUDE or LIB change, or a day later.
- **Only for Neovim.** It runs only as Neovim's child (its parent must be `nvim.exe`, checked against reused process ids; a shim's may be a few levels up, for `:terminal`), raises only a Neovim's window, and ends with Neovim: the watcher waits on Neovim's process and its stdin. That keeps it from being picked up as a general tool; it is no barrier against a program of the same user, which can name itself `nvim.exe` and could call Windows itself. The helper holds no privilege such a program lacks: not elevated, no service, no network.
- **No keystrokes.** It reads only Caps Lock and the IME's mode, polled rather than hooked, since a keyboard hook would see every key; even that state is wiped once used.
- **Nothing from where it starts.** Its libraries load from System32 only (it does not run where that cannot be set), and unless it runs as a shim it leaves the directory Neovim started it in: a repository can plant nothing for it, and the watcher does not keep that directory from being renamed or deleted.
- **Failures.** Exit codes: 0 done, 1 failed, 2 usage, 3 a protocol violation on stdin, 4 not started by Neovim, 127 a shim that cannot run its program; each comes with its reason on stderr. Neovim shows each failure once, with that reason, and lists them in `:checkhealth features.editor`. Without the helper the IME switch falls back to `im-select.exe`; the indicators have no other source.

Style and tests: [development](../development.md#windows-ime-helper).

### Programs from PATH only

`init.lua` sets Windows' own switch, `NoDefaultCurrentDirectoryInExePath`, for Neovim and everything it starts: a program named without a directory comes from PATH, never from the current directory. Without it Windows, libuv (every `vim.system()` and job) and `cmd.exe` look there first, and a repository holding a `clangd.exe` or `rg.exe` would be run for whichever tool the machine lacks. In `:terminal`'s `cmd.exe`, a program of the current directory then takes `.\name`, as in PowerShell. A value set before Neovim starts is kept.

On every system `init.lua` also drops PATH's empty and relative entries (a separator at either end, `;;`, `.`): they name the current directory, and Neovim's own lookups (Vimscript `executable()`, `jobstart()`, `:terminal`, the clipboard provider) would run a program a repository put there despite the switch; on Linux and macOS so would `execvp()`. What is appended to PATH later never leaves one. `require()` does not look in the current directory either: LuaJIT's `./?.lua` and `./?.dll` (`./?.so`) are dropped from `package.path` and `package.cpath`.

### Folders other accounts may change

`:checkhealth features.util` names every PATH folder and registered program's folder that Everyone, Authenticated Users (service accounts too), Users or INTERACTIVE may change, as a folder made directly under `C:\` inherits (`C:\Python314`, `C:\msys64`): a program or DLL put there runs as you, in Neovim and everywhere else. Only an administrator can take that right away; the advice shows how.

### No cmd.exe between Neovim and a tool

A `.cmd` or `.bat` runs through `cmd.exe`, which splits a command at `&` and expands `%NAME%` whatever quoting libuv gives the arguments (it escapes `"` as `\"`, which `cmd.exe` does not know): a formatter handed `C:\a&b\x.lua` would run `b\x.lua`, on save. Every program Mason installs is a `.cmd` on PATH, so `exepath()` answers with the `.exe` or `.com` a Mason `.cmd` names inside Mason's packages, and `vim.system()`, conform and language servers start it directly, with the same arguments and DLL search order; a server ended this way also ends, where killing a `.cmd` left its program running. A formatter npm installs is a `.cmd` that runs `node <script>` (behind Mason's own `.cmd`), so conform starts node with that script itself (`util/windows/npm_launcher.lua`). What still runs through `cmd.exe` is not started for a file whose path holds `& | % ^ < > "`, and Neovim says why once per file: every nvim-lint linter (nvim-lint starts them as `cmd.exe /C`, whoever calls `try_lint()`), and any other formatter that is a `.cmd` or `.bat` (Java's launchers), which then hands the buffer back as it is, so no language server formats it instead. `vim.ui.open()` (`gx`, Snacks' git browse, a language server's `window/showDocument`) hands its target to Windows PowerShell's `[Diagnostics.Process]::Start()` in an environment variable instead of `cmd.exe /c start` (`util/windows/open_target.lua`): it opens as Explorer would, and reads no `[ ]` in a path as a wildcard, as `Start-Process` did. A local file that opening runs (a program or script by `PATHEXT`, a shortcut, an installer, an HTML application, a `.reg`) is not opened. The Ruby debugger is not offered on Windows: rdbg serves a Unix socket, which Neovim reaches there only as a named pipe, or TCP without authentication.

### Faster on Windows

- **Program lookups** (`executable_lookup_cache.lua`): Windows' `executable()` and `exepath()` try every PATHEXT extension in every PATH directory, about 10 ms a name with forty directories. Lua callers (`vim.system()` and plugins included) get the answer from `stdpath("cache")/nvim-config/executable_lookup_cache.json`, kept per PATH with each directory's mtime and rechecked every 2 s. A changed directory drops only its own answers. A bare name never resolves into the current directory unless PATH lists it, so a planted `cl.exe` cannot build the helper.
- **matchit and netrw** load before lazy.nvim fills the runtimepath: `:packadd` resolves every entry, about 20 ms more apiece on a full one.
- **lazy.nvim's update checks** start git once per plugin, and Windows holds the editor about 5 ms per process; they wait until no key has come for 5 s outside a terminal, or until Neovim has been without focus for a second, and start from the main loop, never inside the focus event ([why](../troubleshooting.md#caveats)).

Elsewhere on Windows: [MSVC environment, compile databases, `--query-driver`](lang.md#msvc-toolchain), [LLDB beside gdb](dap.md#choosing-gdb-and-lldb), [Mason's install gate](lsp.md#mason-packages), [program discovery](#programs-registered-by-path).

### Keys and commands

None of its own. `:checkhealth features.util` shows whether the lookup memory is installed and the helper is built.

### What it needs

Visual Studio (or its Build Tools) with the MSVC tools, or clang targeting MSVC, to build the helper.

### Systems

Windows (x86_64) only. On Linux and macOS, `:FeatureStatus` reports it as not supported.
