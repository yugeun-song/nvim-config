# External programs

The programs the configuration runs: Mason's packages, and programs off PATH registered by path. Specs: `lua/plugins/external_programs/`; code: `lua/features/external_programs/`.

## Mason packages

`mason_packages.lua` lists what Mason installs beside LazyVim's defaults, into `stdpath("data")/mason`; [credits](../credits.md) lists every package with its license. Some packages need a runtime on PATH to run (`package_runtime_requirements.lua`), and `:FeatureStatus` warns when an installed one lacks it:

| Runtime | Packages |
|---|---|
| `java` | `detekt`, `jdtls`, `kotlin-lsp`, `ktlint` |
| `elixir` | `elixir-ls`, `expert` |
| `erl` | `elp` |
| `julia` | `julia-lsp` |
| `node` | `js-debug-adapter` and every npm package |

Windows (`mason_windows_install_gate.lua`): Mason does not install a package whose runtime is missing, nor, for 7 days, one whose install failed (`stdpath("state")/nvim-config/mason_install_failures.json`), so a build that cannot work there does not rerun in every session or hold up the exit. `:MasonInstall NAME` retries at once; what is installed stays.

## Programs registered by path

`<leader>uX` (or `:ToolPath`) lists the programs this configuration runs by name (`cscope`, `ctags`, `gdb`, `lldb-dap`, `yazi`, `rg`, `fd`, `tree-sitter`, `ruff`) with the one each resolves to, and registers one by path:

- `stdpath("state")/nvim-config/registered_programs.json` keeps the choice;
- `stdpath("data")/nvim-config/registered_program_shims` holds one shim per program and is the only directory added to PATH, at its end, so nothing beside the program comes into reach and a program already on PATH still wins;
- a shim is a symbolic link; on Windows it is a copy of the [IME helper](windows_platform.md#windows-ime-helper) that runs the program named in `NAME.shim` with the same arguments and exit code, with the program's own directory first on its PATH (so MSYS2's `cscope` finds MSYS2's `sort` for its `-q` index).

With nothing registered this costs one stat at startup. A shim or `.shim` removed by hand is made again at the next start.

On Windows a `.shim` must name an `.exe` or `.com` on a local disk, absolute or relative to the shim's own directory. Drive-relative, rooted, device and network paths, alternate data streams, another shim and the shim itself are refused (a shim naming a shim could loop). A shim runs only with Neovim among its nearest ancestors (`:terminal` included), and its program runs in a job that ends with the shim. A failure goes to its stderr and to `windows_ime_helper_shims.log` beside it, which Neovim watches and shows at once.

On Windows the picker also reads what the system records, on request only (`windows_program_discovery.lua`, one PowerShell run): the machine and user PATH in the registry (programs installed after this Neovim started; one pick adds them to the session), App Paths, the install locations of installed programs with their usual bin directories, Visual Studio's LLVM tools through vswhere, and the winget, Scoop, Chocolatey and Cargo directories their variables name. The result is kept in `stdpath("state")/nvim-config/windows_program_discovery.json`; nothing is registered until picked.

The picker also turns the [MSVC environment](languages.md#msvc-toolchain) off and on.

## Keys and commands

| Command | Does |
|---|---|
| `:ToolPath` | Pick a program and register it (`<leader>uX`) |
| `:ToolPath NAME` | Ask for NAME's path |
| `:ToolPath NAME PATH` | Register NAME as PATH (a relative PATH is taken from the current directory) |
| `:ToolPath! NAME` | Forget NAME |

## What it needs

The runtimes above; `:checkhealth mason` lists what Mason's installers need. Shims need nothing more on Linux and macOS; on Windows they need the [IME helper](windows_platform.md#windows-ime-helper).

## Systems

| Part | Linux | macOS | Windows |
|---|---|---|---|
| Mason packages | yes; one with no build for the machine is reported as not supported | yes | yes, with the install gate |
| Programs registered by path | yes | yes | yes |
| Discovery from the system's records | no | no | yes |
