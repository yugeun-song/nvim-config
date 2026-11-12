# Development

The rules every change follows, and how to check and test one.

## Goals

1. **Heavy yet light.** Many features, little cost: each loads when needed and is released when unused, stays fast, hardcodes next to nothing, and takes what it needs from official, verifiable sources.
2. **Windows never costs Linux or macOS.** Windows work sits behind `has("win32")`; it must not slow down or degrade the other systems ([lazy loading](structure.md#lazy-loading)).

## Naming and style

- Names say what a thing does and are intuitive first. Long is fine; a name that is already clear is not lengthened.
- Lua files and modules are snake_case and named by what they do, in LazyVim's categories: a spec at `lua/plugins/<category>/<name>.lua`, its code at `lua/features/<category>/<name>.lua` or in `lua/features/<category>/<name>/` ([structure](structure.md)).
- Comments are compact and appear only where the code alone is unclear or a judgment was made; they say why.
- One comment syntax per file; in C that is `//`.
- Lua: StyLua (`stylua.toml`: 2 spaces, 120 columns). A blank line follows a statement that spans several lines and a run of `local` declarations, and precedes `return`.
- C (`native/windows_ime_helper.c` and its tests) follows Microsoft's Windows layout (`native/.clang-format`, clang-format 21 or later):
  - braces on their own line, and on every body;
  - globals `g_`, file-static globals `gs_`;
  - booleans named with a be-verb (`isCrashed`);
  - `++i`, `while (1)`, `{ 0 }` with spaces;
  - each function leaves through one `Cleanup` exit that frees what it acquired and wipes what it filled.
- Markdown passes rumdl with `.rumdl.toml` (line length, MD013, is not checked).

## Checking the repository

`nvim -l scripts/check_repository.lua [--fix] [--verbose]` runs these steps:

| Step | Checks | `--fix` |
|---|---|---|
| `blank-lines` | the Lua blank-line rule above, read through tree-sitter | inserts the lines |
| `stylua` | `stylua --check .` | `stylua .` |
| `lua_ls` | `lua-language-server --check` at Warning, with Neovim's runtime and the installed plugins as library | |
| `taplo` | `taplo fmt --check` on the tracked `*.toml` | `taplo fmt` |
| `rumdl` | `rumdl check .` | `rumdl fmt .` |
| `clang-format` | `--dry-run --Werror` with `native/.clang-format` on the tracked `*.c` | `-i` |
| `credits` | `scripts/update_credits.lua --check` | `--write` |

Each tool comes from PATH, else Mason's `bin`; a missing tool prints `skip`. A FAIL prints its findings and ends with exit code 1; `--verbose` prints every step's output.

## Credits

`nvim -l scripts/update_credits.lua --write` rewrites the block between `<!-- credits:start -->` and `<!-- credits:end -->` in [credits](credits.md): plugins from `lazy-lock.json` and their LICENSE files, Mason packages from every spec in `lua/plugins/`, LazyVim's defaults and Mason's registry, and the script's own lists (code taken in, programs run, the closing notes). `--check` fails when the block is out of date. Without the plugins installed or Mason's registry downloaded it prints `skipped`.

## Tests

No CI: every test runs by hand.

### Containers (Linux host)

`sh tests/containers/run.sh [--keep] [--rebuild] [DISTRIBUTION...]` tests the configuration in official distribution images through rootless podman: arch, debian (stable), ubuntu (LTS), fedora, rocky (10), opensuse (Tumbleweed), void, nixos, gentoo.

1. Host, once per lockfile: the official Neovim 0.12.6 build (SHA-256 checked), the locked plugins and their parsers, in an isolated directory.
2. Per distribution, with network: its Neovim and test tools, a test user, the official build (not on NixOS) and the plugins, kept as `localhost/nvim-config-test/<name>:prepared`. Gentoo uses the official build only.
3. Per distribution, without network: `tests/managed_paths/run.sh --installed` for each Neovim, and `startup_check.lua`: the whole configuration opens C, assembler, Python, Markdown and Lua files and runs every health check, with no Lua error, error notification or failed check. Neovim before 0.11.2 must be refused with LazyVim's message.

Only this command starts it. When it ends or is interrupted it removes everything of these tests by default: the containers and images labelled `org.nvim-config.test=containers`, the official images it pulled, the host directory, its records and logs. `--keep` keeps them (a later run reuses a prepared image while `lazy-lock.json` is unchanged; `--rebuild` prepares again), and `--clean` removes them later. Images that were there before, and anything without the label, are never touched. Each prepared image keeps its base image's digest as a label, and the summary shows it: the tags follow the newest release, so the digest says which build was tested. Signatures are not checked: on 2026-11-11 openSUSE published a cosign signature for its image, the three Docker Official Images carried Docker's build provenance, and the other five neither. podman is the only engine: it needs no root daemon, and its policy can check cosign signatures, while Docker's Notary signatures no longer matched those images' current builds. The runs stay offline, without new privileges, under memory and process caps, with the repository mounted read-only. Logs, kept only with `--keep`: `${XDG_STATE_HOME:-~/.local/state}/nvim-config-container-tests/logs/<run>/`.

### Managed paths

`tests/managed_paths/check.lua` holds each Neovim to its directory rules and `lua/features/util/managed_paths.lua` to what it lists and what a reset removes and keeps. Every variant runs in a throwaway root that `HOME` and every directory point into; nothing outside it is removed.

| Command | System | Runs |
|---|---|---|
| `sh tests/managed_paths/run.sh [--release] [--flatpak ID] [NVIM...]` | Linux, macOS | variants default, xdg, appname, appname-nested, flatpak-sim, overlap, nested; then the reset's question, piped (nothing removed) and typed through `script(1)` (removed). `--release` adds the official 0.12.6 build, SHA-256 checked (skipped where it cannot run, such as NixOS or musl); `--installed` the user's real layout, only inside the containers of `tests/containers/run.sh`; `KEEP_ROOT=1` keeps the root. |
| `powershell -ExecutionPolicy Bypass -File tests\managed_paths\run.ps1 [-Nvim nvim] [-KeepRoot]` | Windows | the same variants without flatpak-sim; only the piped answer, since typing needs a console |

### MSVC compile database

`nvim -l tests/msvc_compile_database/check.lua` runs on any system, in a throwaway root:

- everywhere: how a cl command line is split and becomes a clangd entry, how a solution configuration's projects are read, how a configuration is chosen;
- on Windows with Visual Studio, through MSBuild for real: solutions the test writes itself (`.sln` and `.slnx`, under a directory named with a space, Korean and `&`) must resolve `$(SolutionDir)`, read the solution's `x86` as the projects' `Win32`, refuse a configuration the solution has not, name a toolset or Windows SDK version that is not installed, keep the other projects' entries when one cannot be loaded, be rebuilt on opening a file only when behind, and leave a database that would say the same untouched. clangd, when there is one, must read a source of them without a diagnostic. Elsewhere these steps print SKIP.

### Focus events

`nvim -l tests/focus_events/check.lua` runs on any system: nothing may work or wait inside a `FocusLost` or `FocusGained` autocmd, where Neovim drops the next focus event ([why](troubleshooting.md#caveats)). It holds the deferred lazy.nvim update check to that.

### Windows IME helper

`powershell -ExecutionPolicy Bypass -File tests\windows_ime_helper\run.ps1 [-FuzzSeconds 60] [-Nvim nvim]` builds and runs every test in a temporary directory and prints PASS, FAIL or SKIP per step:

- clang-format with `native/.clang-format`;
- `cl /W4 /WX /sdl /analyze`, clang `-Wall -Wextra -Werror` and `--analyze`;
- the preprocessor guards: Linux, macOS, MinGW, 32-bit and ARM64 targets must fail;
- `unit.c` (C unit tests) and `test.lua` (Neovim-driven; it switches the foreground IME to English and raises a window) under AddressSanitizer;
- `bridge.lua`, the Lua side's tests, which also run alone on any system, each in a throwaway root: `nvim -l tests/windows_ime_helper/bridge.lua`;
- `fuzz.c`, a libFuzzer target over the parsers.

It needs Visual Studio 2022 or later with the C++ tools and enters a Developer PowerShell itself. Without clang or clang-format those steps are SKIP.
