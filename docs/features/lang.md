# Languages

C and the Linux kernel first: clangd, cscope and `tags` tuned for big trees, assembly that reads right, CUDA and Visual Studio projects in clangd; then Lisp, Racket, Haskell, Lean, Python, Elixir, Rust, TypeScript and Markdown. One spec file per language in `lua/plugins/lang/`, with its parsers, Mason packages, servers, formatters, linters and debugger; code: `lua/features/lang/`, `after/`, `queries/`.

## C and C++

- **Indentation** (`c/indentation.lua`). A `.clang-format` found upward sets it (`IndentWidth`, `UseTab`, `TabWidth`, or the `BasedOnStyle` default); a project `.editorconfig` wins over it. With neither, a buffer whose first 2000 lines start more often with a tab than with two spaces gets 8-column tabs, else 4 spaces. Existing whitespace is never rewritten: `list` is on and autoformat off.
- **clangd** (`lua/plugins/lang/c.lua`, `c/clangd.lua`): `--background-index --clang-tidy --completion-style=detailed --header-insertion=never --pch-storage=disk --background-index-priority=background --limit-results=200 --limit-references=2000 --log=error -j=<all CPUs>`. Its temporary files go to a private directory per Neovim under `stdpath("cache")`, removed when that Neovim exits.
- **cscope**: cscope_maps.nvim with Telescope under `<leader>i`, loaded by its commands and keys. A query reads only the nearest `cscope.out` above the current buffer, so one tree never answers for another. cscope reads assembler as C, so `find g` drops an assembler hit only when its line proves a use and its file spells nothing else that could define the word; every hit stays when all would go.
- **`<C-]>`** jumps through `tags` (`make tags`): the language server's `tagfunc` is cleared in C, C++ and assembler buffers. `'tags'` searches upward from the buffer and ignores the working directory.
- **`gf` on `#include`** (`c/include_gf.lua`): with a project `compile_commands.json` or `compile_flags.txt`, clangd's header when it is in the project or a system one; else a matching `tags` entry, `cscope.out` file or `cscope.files` line (a picker when several match); else the built-in `gf`.
- **All `#if` branches** (`c/all_ifdef_branches/`): `<leader>uB` colours every preprocessor branch and answers hover, definition and completion in the inactive ones through extra clangd instances (at most 8). Off by default; the choice is saved and every running Neovim follows it.

## Assembly

- **Filetypes**: `.S`, `.s`, `.sx` are `asm`; `*.lds` and `*.lds.S` are `ld`. Parsers: `asm`, `c`, `cpp`, `linkerscript`, `devicetree`.
- **`.S` and `.s`**: a line that starts with a preprocessor directive is parsed as C (`after/queries/asm/injections.scm`); a `#` comment after an instruction stays a comment. This is injection, not preprocessing: `#if 0` bodies stay highlighted.
- **Assembly colours** (`asm/syntax_highlighting.lua`) in `asm` buffers and in the `asm("…")` templates of C, C++ and CUDA, since tree-sitter-asm misparses labels, dotted mnemonics and GCC operands (`queries/asm/highlights.scm` keeps only its comments and strings). CUDA's device templates are PTX: its registers (`%r1`, `%rd1`, `%%tid.x`), operand types (`.u32`, `.pred`), guards (`@p`) and `{ }` scopes read as such. A token it does not know stays plain.
- **Macro bodies** (`c/macro_body_highlighting.lua`): after `#x`, `a##b` or a macro used as an `asm` template, tree-sitter can drop a quote and swap strings and code. A `#define` body is re-parsed with those constructs masked, a function line gets lexer colours, and `asm` templates keep their assembly colours.
- **`gd` and `K` in assembler** (`asm/definition_navigation.lua`), in order:
  1. clangd's answer for a word's `#define` or on an `#include` line;
  2. the definitions in the file itself, from `tags` or spelled on a line (label, `=`, `.set`, `.equ`, `.macro`, `.req`), alone unless `#if` or `.if` encloses them;
  3. every place that may define the word, nearest first: the files it includes, macro calls in this file (`SYM_FUNC_ALIAS(name, ...)`), a macro of this file taking the word, all other tags, what cscope spells, and macro calls at file scope (`DEFINE_PER_CPU(type, name)`);
  4. prototypes and other tags that define nothing, then a macro's arguments elsewhere, then the built-in `gd`.

  One hit jumps; several open the `<leader>i` Telescope picker. A `\name` operand is a `.macro` parameter and goes straight to the built-in `gd`. A second clangd (`clangd_asm`: no background index, no tidy) attaches to `asm` buffers and leaves any the project's clangd configuration cannot read as C; it offers only those two answers, no completion, tokens, formatting or diagnostics. `<leader>is` lists a symbol's uses.

## CUDA

clangd reads `.cu` and `.cuh` files in clang's CUDA mode on every system (`lua/plugins/lang/cuda.lua`, `cuda.lua`); nothing here runs for C or C++ files.

- **nvcc compile commands.** A database written for nvcc (CMake's, Bear's) holds options clang does not take. An open CUDA file whose command is nvcc's gets the clang command that compiles it the same way (include directories, definitions, standard, the first GPU of `-arch` or `-gencode`, the toolkit nvcc belongs to) through clangd's `compilationDatabaseChanges`. The database is not touched; a command that is already clang's is left alone.
- **nvcc-only spellings.** clang lexes only `<<<` and `>>>`; its errors on a launch written `k << <grid, block >> > (args)`, as Visual Studio's formatter writes it, are dropped, and so is "not used directly" for `cuda_runtime.h`, `cuda_runtime_api.h`, `cuda.h` and `device_launch_parameters.h`. Every other diagnostic stays.
- **No compile command.** clangd's fallback flags name the toolkit in `CUDA_PATH`, else the one `nvcc` on PATH belongs to.

## MSVC toolchain

Windows only (`c/msvc_toolchain/`).

- **Developer environment** (`developer_environment.lua`): vswhere finds the newest Visual Studio with the MSVC tools; its `VsDevCmd` runs once in the background, and what it changes is kept in `stdpath("state")/nvim-config/msvc_developer_environment.json`. Each start sets those variables (`INCLUDE`, `LIB`, `LIBPATH`, the VCTools and Windows SDK ones; none already set is replaced) and appends the directories to PATH: clangd reads `INCLUDE`, and `:terminal` and `:make` get `cl`, `link`, `nmake` and `msbuild`. A start from a Developer Prompt changes nothing; a Visual Studio update is captured again; `<leader>uX` turns it off and on.
- **Compile databases** (`compile_database.lua`): MSBuild's design-time target `GetClCommandLines` gives the cl options of every source file, as IntelliSense reads them. All projects of the nearest `.sln`, `.slnx` or `.vcxproj` go through one MSBuild run, and `compile_commands.json` goes beside that file. CUDA projects' `.cu` files come from the same run, with the toolkit, GPU, defines and include directories NVIDIA's build customization resolves; nothing is compiled. MSBuild runs what a project defines, so the first database of a project is made only by `:MsvcCompileDb`; opening a file of a project without one says so. From then on, opening a C, C++ or CUDA file rebuilds it in the background when an input changed (the solution, each `.vcxproj`, the `.props` and `.targets` they import, `Directory.Build.*`), and writing one of those in Neovim checks again. A `compile_commands.json` it did not write is left alone. `vim.g.msvc_compiledb_auto = false` keeps it to `:MsvcCompileDb`.
- **MinGW**: clangd gets `--query-driver` for the directories of the compilers on PATH, so a database written for MinGW's gcc gets gcc's target and system includes; nothing a repository names is run.

## Common Lisp

- The `commonlisp` parser highlights `lisp` buffers. [alive-lsp](https://github.com/nobody-famous/alive-lsp) runs in SBCL as the language server, enabled when `sbcl` is on PATH and its directory holds `ocicl.csv`. `ocicl lint` adds INFO diagnostics on read and write. `'` and `` ` `` are not auto-paired and nothing is formatted on save. `.el` files get neither server, linter nor REPL keys.
- `scripts/alive_lsp_over_stdio.lisp` runs alive-lsp over stdio instead of a TCP port, turns `*read-eval*` off, and reshapes the hover, definition, formatting and shutdown replies. It calls alive's internal `create-deps`: re-check it before moving the pin.
- Install alive-lsp into `stdpath("data")/nvim-config/alive_lsp` (`~/.local/share/nvim/nvim-config/alive_lsp` on Linux), pinned to the v0.4.5 commit:

  ```sh
  mkdir -p ~/.local/share/nvim/nvim-config/alive_lsp && cd ~/.local/share/nvim/nvim-config/alive_lsp && : > ocicl.csv
  OCICL_LOCAL_ONLY=1 ocicl install git+https://github.com/nobody-famous/alive-lsp@85f118b85d1543bb7413166b6793b87975b4d439
  ```

- **REPL** (`lisp/repl.lua`): `sbcl` in a bottom terminal split, started in the project root (`ocicl.csv`, `.git` or an `.asd`). Code reaches it through a temporary file that `(nvim-repl:ev …)` reads and deletes, never through the pty; no socket is opened, and ocicl's `*download*` is off.

## Racket

`racket` alone: the `racket` parser highlights, Neovim's runtime indents, and its racket ftplugin makes `K` run `raco docs`. No language server. The REPL is `racket -i` in a bottom terminal split, in the nearest folder with `info.rkt` or `.git`; under `TERM=dumb` xrepl reads plain lines and saves no history, and forms go through temporary files the REPL deletes after `,ld`.

## Haskell

[haskell-tools.nvim](https://github.com/mrcjkb/haskell-tools.nvim) (`^11`) runs haskell-language-server for Haskell and Cabal files (lspconfig's `hls` is off), with the `haskell` parser and `hlint`. GHCup's `bin` (`haskell.lua`: `~/.ghcup/bin`, `C:\ghcup\bin`, or under `GHCUP_INSTALL_BASE_PREFIX`) is appended to PATH when Haskell is first needed, so an earlier program of the same name wins.

## Lean, Python, Elixir, Rust, TypeScript

- **Lean 4**: lean.nvim, with the server from elan (`lake serve` runs the toolchain the project pins), not Mason; the infoview opens at the bottom.
- **Python**: `ty` (Mason) for types and hover; `ruff`, when on PATH, lints (hover off) and formats through conform; debugpy through nvim-dap-python.
- **Elixir**: `expert` is the only server; `elixir-ls` stays for debugging. Each session gives Expert a random cookie instead of the public `expert` one and keeps its manager on loopback.
- **Rust**: rustaceanvim runs its own rust-analyzer (lspconfig's is off); a file outside a cargo project gets `RUSTC_BOOTSTRAP=1` and no cargo autoreload.
- **JavaScript and TypeScript**: `vtsls` and `oxlint`; js-debug for nvim-dap, under the names a VS Code `launch.json` uses too.

Their debuggers: [debugging](dap.md#programs).

## Markdown

markview.nvim renders Markdown in place (`markdown.lua`); it loads at startup, as its README asks. `rumdl` lints.

## Tree-sitter parsers

Each language file adds its own parsers; `lua/plugins/treesitter.lua` adds those of the languages without one (`awk`, `css`, `dockerfile`, `erlang`, `git_config`, `git_rebase`, `gitattributes`, `gitcommit`, `java`, `julia`, `kconfig`, `kotlin`, `make`) to LazyVim's list.

## Keys and commands

| Command | Does |
|---|---|
| `:MsvcCompileDb [Configuration] [Platform]` | Windows: rebuild `compile_commands.json` from the nearest `.sln`, `.slnx` or `.vcxproj` now, and keep that configuration for the automatic rebuilds (Debug and the machine's platform by default) |
| `:Cscope`, `:Cs` | cscope_maps' commands; the `<leader>i` keys run `:Cscope find …` |

Keys: [C and kernel navigation](../keymaps.md#c-and-kernel-navigation), [Haskell, Common Lisp, Racket](../keymaps.md#languages).

For a kernel tree, generate the indexes first: [installation](../installation.md#requirements).

## What it needs

| Part | Programs |
|---|---|
| C and C++ | `clangd`, `cscope`, `ctags` |
| CUDA | the CUDA toolkit |
| Assembly | the `asm` parser |
| MSVC toolchain | Visual Studio with the MSVC tools, MSBuild through vswhere |
| Common Lisp | `sbcl`, `ocicl`, alive-lsp |
| Racket | `racket` |
| Haskell | `ghc`, `cabal`, `haskell-language-server`, `hlint` |
| Lean | `elan` |
| Python | `ruff` |
| Parsers | the `tree-sitter` CLI, a C compiler, `curl`, `tar` |

## Systems

Everything runs on Linux, macOS and Windows, except the MSVC toolchain (Windows only). cscope has no native Windows build: register one by path ([installation](../installation.md#windows)).
