# Debugging

C, C++ and assembly are debugged by GDB itself (`gdb -i dap`), so `~/.gdbinit`, pwndbg and other GDB Python tooling load as usual; LLDB serves where gdb cannot. Specs: `lua/plugins/debugging/`; code: `lua/features/debugging/` (`nvim_dap_setup.lua`, `sessions/`, `views/`, `qemu/`, `linux_kernel/`).

## Adapters

| Language | Adapter | What it brings |
|---|---|---|
| C, C++, assembly | `gdb` (`gdb -i dap`) | every panel below, QEMU user mode, gdbtools |
| Linux kernel | `gdb_linux_kernel` (`gdb -i dap`; `gdb_kernel` is its older name, kept for older `launch.json` files) | the same, plus kernel attach |
| C, C++ (macOS, Windows) | `lldb` (`lldb-dap` or `codelldb`) | launch, launch to `main`, attach; Registers, Memory, Disassembly; function and address breakpoints |
| Python | nvim-dap-python on `debugpy` | its configurations, the test under the cursor |
| Rust | rustaceanvim on `codelldb` | `:RustLsp debuggables` |
| JavaScript, TypeScript | `js-debug-adapter` | `pwa-node`, `pwa-chrome`, `pwa-msedge`; `.ts` on Node's type stripping, or `tsx` or `ts-node` when installed |
| Elixir | ElixirLS's `mix_task` | `mix test`, `mix run` |

`.vscode/launch.json` is read for every language. The rest of this page is about the `gdb` and `gdb_linux_kernel` sessions; an `lldb` session gets the Registers, Memory and Disassembly panels and the function and address breakpoints, and the others plain nvim-dap-view.

## Choosing gdb and LLDB

- **gdb** for a target: `vim.g.dbg_gdb` (a name or path, or a table by architecture), else the first `<triple>-gdb`, `gdb-multiarch` or host `gdb` that runs DAP (gdb 14 or later with Python) and knows the architecture. One run of each candidate tells; a broken one is skipped with a notice. With none, the session does not start and names the package to install. Windows also looks in MSYS2 (`C:\msys64\ucrt64\bin`, `mingw64`, `clang64`). Kernel sessions run kbuildlab's gdb.
- **LLDB**: `vim.g.dbg_lldb`, else Xcode's `lldb-dap`, Mason's `codelldb`, an `lldb-dap` on PATH, or Homebrew's llvm. Offered on macOS and Windows; setting `vim.g.dbg_lldb` offers it anywhere.
- **kbuildlab**: `vim.g.dbg_kbuildlab` or `$KBUILDLAB`, else the one on PATH, else the checkout its installer recorded. **gdbtools**: `$GDBTOOLS_PATH`, else the checkout its `setup.sh` recorded; sourced into each gdb when installed.

## Programs

Launch, launch to `main`, attach by PID, *Run on QEMU user* and *Attach to a QEMU user gdbstub* (Linux: `qemu-<arch> -g` on a private Unix socket with the toolchain's sysroot, stopped at `_start`; x86_64, aarch64, riscv64, arm). The executable and shell-quoted arguments are remembered: `<leader>dc` with no session replays the last run, `<leader>dn` asks again.

## Linux kernels

- `<leader>dq` lists the guests from `kbuildlab attach --list --json` (tree, boot mode, KASLR, whether a debugger holds the stub; a busy stub is refused); a guest kbuildlab did not start is attached by picking its registered tree and port. It then asks: attach where the kernel is, or early boot (`:DbgLinuxKernelEarly` skips the question), which runs `kearly on` and `kearly bootbreak arm` and continues to the first `head.S` instruction.
- Each start asks `kbuildlab attach TREE --port N --json` for the gdb, its `-iex` lines, gdbtools, the vmlinux, the target and QEMU's pid, so a replayed configuration follows a guest restarted in another boot mode. A vanished QEMU or a lost connection is announced, and the panels stay.
- **Guarded reads.** A read outside guest RAM can take QEMU down, so under `:DbgSafeMem auto` a kernel session checks the address with `monitor gva2gpa` and `gpa2hva` on every core, reads physical-only RAM through `monitor xp`, and refuses a device region or hole. `o` in the hex view reads anyway; `on` and `off` guard every session or none.

## Session behaviour

- **All-stop remotes.** A remote target takes no command while it runs: a breakpoint change is held, the target interrupted unseen by nvim-dap, the change sent, the target resumed. If it does not stop within 2 s, the change waits for its next stop.
- **Stopping.** `<leader>dt` detaches an attached target (interrupting it first) and terminates a launched one; `<leader>dT` kills, ending a QEMU guest. Quitting Neovim ends every session the same way and kills any leftover `gdb -i dap`.
- **Breakpoints.** Line breakpoints are allowed without DWARF (a library may carry it); refused ones are reported with gdb's message, unbound ones with the likely reason. `<leader>dF` breaks on a function or `0x` address with no line table. A breakpoint gdb makes itself (the stop-at-`main` one) never replaces yours.
- **Run to cursor.** `<leader>dC` runs to the source line or disassembly address under the cursor through gdb's own one-shot breakpoint, so your breakpoints stay (nvim-dap's would clear them all).
- **Frames and stepping.** The selection returns to frame 0 after nvim-dap picks a caller with source, so every view agrees; without source, steps go by instruction and the disassembly is shown.
- **Windows.** Source opens in a file window, never a panel; ending a session closes nothing. `<leader>du` toggles the panel; `:DbgClose` restores the layout from before the session.

## Panels

nvim-dap-view tabs, switched by the letter in their label: Scopes, Locals+Globals (frame and file variables, `static` included, optimised-out ones tagged `opt`), Watches, Registers (`<symbol+offset>`, change marks), Memory (hex view of an expression, a physical address or a file, 8 KiB per window), Mappings (pwndbg's `vmmap`), Control flow (gdbtools' `cfgjson`), Disassembly (pc highlight, a connector to a taken branch), Call stack, Breakpoints, Target, the gdb console and Output.

A stop refreshes only the panels on screen; a hidden one catches up when shown. Target asks fixed facts (architecture, endianness, checksec) once per session. Values also show at the end of the lines that use them (`:DbgInline off`).

The **gdb console** is GDB's own interpreter with ANSI colours. `c`, `n`, `s`, `ni`, `si`, `finish`, `q` and `kill` go through nvim-dap so the panels stay in step; `<CR>` runs the line under the cursor; `<C-x><C-o>` completes.

**Layout** depends on `columns` and `lines` only: compact keeps every panel in the bottom bar; wide adds a right-hand column with one panel, Registers first. `:DbgLayout` overrides, `:DbgLayoutReset` rebuilds the windows.

| Panel | Keys |
|---|---|
| Hex view | `t` source, `L` layout, `w` bytes per row, `g` bytes per group, `+` `-` rows, `]]` `[[` page, `<CR>` follow pointer, `p` `x` `s` pin, unpin, switch, `e` byte order, `A` ASCII column, `N` symbol annotation, `W` width fitting, `a` auto refresh, `o` read past the guard |
| Registers | `f` filter, `<CR>` value in the hex view |
| Locals+Globals | `f` filter, `<CR>` pin to Watches, `K` gdbtools' `addr2sym` for the address on the line (it does not read it) |
| Control flow | `p` back to the pc, `<CR>` source line, `+` `-` (or `=` `_`) detail, `H` `J` `K` `L` move by block |
| Mappings | `<CR>` region in the hex view |
| All of these, Target | `r` refresh |
| Side column | `]p` `[p` switch the panel |
| Target report, log | `q` close |

## Keys and commands

| Command | Does |
|---|---|
| `:DbgLinuxKernel` | Pick a kbuildlab guest and attach; asks where |
| `:DbgLinuxKernelEarly` | The same, armed for early boot (`GDBTOOLS_AUTO=1`) |
| `:DbgTargets` | The guests kbuildlab sees on this machine |
| `:DbgMemory [expr\|file]` | Open the hex view |
| `:DbgRegisters`, `:DbgMappings` | Open the register or memory-map panel |
| `:DbgControlFlow` | The control-flow graph in the source window; again to go back |
| `:DbgSafeMem on\|off\|auto` | Guard memory reads against QEMU device regions (`auto`: kernel sessions) |
| `:DbgLayout auto\|wide\|compact` | Switch the window layout |
| `:DbgLayoutReset` | Rebuild the debugger windows, leaving the session and breakpoints alone |
| `:DbgBreak [name\|0xADDR]` | Toggle a breakpoint on a function or address, no line table needed |
| `:DbgBreakpoints` | Every breakpoint in a picker |
| `:DbgState` | What this session supports (line, function and instruction breakpoints, source stepping, disassembly, QEMU monitor), and why not |
| `:DbgClose` | Close every debugger window and restore the previous layout |
| `:DbgInline [on\|off]` | Values where they are used; toggles without an argument |
| `:DbgLog` | The last 400 messages and the tail of nvim-dap's log |

Keys: [keymaps](../keymaps.md#debugging).

## What it needs

| For | Programs |
|---|---|
| C, C++, assembly | `gdb` 14 or later with Python |
| LLDB sessions | `lldb-dap` (Xcode 16 tools) or Mason's `codelldb` |
| Foreign architectures | a gdb for the target; `qemu-<arch>` (or `qemu-<arch>-static`); a sysroot in `/usr/<triple>` or `/usr/<triple>/sys-root` for dynamic programs |
| Linux kernels | [kbuildlab](https://github.com/yugeun-song/kbuildlab); without it kernel debugging is off |
| Early-boot symbols, `cfgjson`, `addr2sym` | [gdbtools](https://github.com/yugeun-song/gdbtools) (optional) |
| Python, Rust, JS/TS, Elixir | `debugpy`, `codelldb`, `js-debug-adapter`, `elixir-ls` (Mason) |

## Systems

| Part | Linux | macOS | Windows |
|---|---|---|---|
| gdb sessions | yes | not on Apple silicon | yes, with MSYS2's gdb |
| LLDB sessions | with `vim.g.dbg_lldb` | yes | yes, for MSVC builds whose PDB gdb cannot read |
| QEMU user mode, Linux kernels | yes | no | no |
