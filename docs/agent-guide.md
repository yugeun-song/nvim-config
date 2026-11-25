# nvim-config

A LazyVim-based Neovim configuration for Linux kernel and C development. It adds a debugger on GDB's own DAP, language server rules per path, Korean input-method integration, a keystroke display, a hand-written colorscheme and a Neovide profile.

- Read `docs/development.md` before a change: it holds the goals, the naming and style rules, and how to check and test a change. `docs/structure.md` says where each file belongs and how plugins load lazily.
- Check a change with `nvim -l scripts/check_repository.lua`; `--fix` applies what the tools can fix. It runs the blank-line rule, StyLua, lua_ls, taplo, rumdl, clang-format and the credits check, and prints `skip` for a tool it cannot find.
- No CI exists, and every test runs by hand. `docs/development.md`, section "Tests", gives each command and the system it needs. `nvim -l tests/focus_events/check.lua` and `nvim -l tests/msvc_compile_database/check.lua` run on any system.
- A spec goes in `lua/plugins/<category>/<name>.lua`, and its code in `lua/features/<category>/<name>.lua` or `lua/features/<category>/<name>/`. A helper module does not belong under `lua/plugins/`, because lazy.nvim reads the files there as specs. Every plugin the configuration adds states a load trigger, and Windows-only work sits behind `has("win32")`.
- Update the documentation with the code. `docs/keymaps.md` lists every key the configuration adds, and `docs/features/<category>.md` describes each category's features, keys, needs and supported systems. `nvim -l scripts/update_credits.lua --write` rewrites the credits block in `docs/credits.md`, and `check_repository.lua` fails while that block is out of date.
- Each kernel debugging session asks `kbuildlab attach TREE --port N --json` for its gdb setup, and the control-flow panel reads gdbtools' `cfgjson`. `docs/features/dap.md` describes both in "Linux kernels" and "What it needs".
