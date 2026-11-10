# Keymaps

The keys this configuration adds to LazyVim's. `<leader>` is Space and `<localleader>` is `\` (LazyVim's defaults). `<leader>sK` (or `:KeyCheatSheet`) lists every key live: these, LazyVim's, the plugins' and Neovim's built-ins, with where each was made.

## General

| Key | Action | Feature |
|---|---|---|
| `<leader>sK` | Every key, mapped and built-in | [help](features/editor.md#key-cheat-sheet) |
| `<leader>fo` | Open Folder in yazi (only with `yazi` installed) | [editing](features/editor.md#open-folder) |
| `<leader>fp` | Projects: opened folders and git roots of recent files | [editing](features/editor.md#open-folder) |
| `<leader>ba` | All buffers in a picker | [appearance](features/ui.md) |
| `<leader>uR` | Reload changed files, refresh the explorers | [editing](features/editor.md#changes-on-disk) |
| `<leader>uK` | Toggle the ChKeys keystroke display | [appearance](features/ui.md) |
| `<leader>uP` | Toggle Discord Rich Presence | [integrations](features/util.md#discord-rich-presence) |
| `<leader>uX` | Tool paths: what each program resolves to; register one by path | [external programs](features/util.md#programs-registered-by-path) |
| `<leader>uM` | Managed paths: where everything is kept (the reset has no key) | [maintenance](features/util.md#managed-paths) |
| `n` `N` `*` `#` `g*` `g#` | Search, with the `[current/total]` index | [appearance](features/ui.md) |
| `h` `l` `<Left>` `<Right>` | In leading spaces, step by `shiftwidth` (arrows in Insert mode too) | [editing](features/editor.md#editing) |
| `<CR>` in mini.files | Open a file and close the explorer, or enter a directory | [editing](features/editor.md#editing) |

## C and kernel navigation

| Key | Action |
|---|---|
| `<leader>is` | cscope: this symbol |
| `<leader>ig` | cscope: this global definition |
| `<leader>ic` | cscope: functions calling this function |
| `<leader>id` | cscope: functions called by this function |
| `<leader>it` | cscope: this text |
| `<leader>ie` | cscope: this egrep pattern |
| `<leader>if` | cscope: this file |
| `<leader>ii` | cscope: files including this file |
| `<leader>ia` | cscope: assignments to this symbol |
| `<C-]>` | Jump through `tags` in C, C++ and assembler |
| `gf` | On an `#include` line, the project's header |
| `gd`, `K` | In assembler: definition and hover |
| `<leader>uB` | Toggle all `#if` branches |

Details: [languages](features/lang.md#c-and-c).

## Language server attach rules

| Key | Action |
|---|---|
| `<leader>cLf` | Exclude the current file |
| `<leader>cLd` | Exclude the file or an ancestor directory |
| `<leader>cLa` | Add a rule: path, servers, action |
| `<leader>cLl` | The action and its source for this buffer |
| `<leader>cLe` | Edit the rules file |
| `<leader>cLr` | Reload the rules |
| `<leader>cLt` | Toggle every rule for this session |

Details: [language servers](features/lsp.md#attach-rules).

## Debugging

| Key | Action |
|---|---|
| `<leader>dc` | Run or continue; with no session, replay the last configuration |
| `<leader>dn` | End any session and start anew, choosing configuration, program and arguments again |
| `<leader>db` / `<leader>dB` | Toggle a breakpoint / a conditional one |
| `<leader>dF` | Break on a function name or `0x` address (works without `-g`) |
| `<leader>dg` | Every breakpoint (line, function, address) in a picker |
| `<leader>dC` | Run to the cursor; in the disassembly, to the address under it |
| `<leader>di` / `<leader>do` / `<leader>dO` | Step into / over / out; by instruction without a line table |
| `<leader>dj` / `<leader>dk` | Down / up the call stack |
| `<leader>dP` | Pause |
| `<leader>dt` | Stop: detach when attached, terminate a launched process |
| `<leader>dT` | Terminate for real (kills a QEMU guest) |
| `<leader>dl` | Run the last configuration |
| `<leader>du` | Toggle the debug panel |
| `<leader>de` / `<leader>dw` | Evaluate under the cursor / add a watch (Normal and Visual) |
| `<leader>dr` | Toggle the debug console |
| `<leader>dR` / `<leader>dm` / `<leader>dD` | Registers / hex view / disassembly (gdb and LLDB sessions) |
| `<leader>ds` | Target panel (gdb sessions) |
| `<leader>dq` / `<leader>dQ` | Attach a kbuildlab guest / list the guests |
| `<leader>dLt` / `<leader>dLc` | Debug the Python test method / class under the cursor |
| `<leader>dLr` | Pick a cargo target to debug (`:RustLsp debuggables`) |

Panel keys and commands: [debugging](features/dap.md#panels).

## Languages

| Key | Buffers | Action |
|---|---|---|
| `<localleader>e` | Haskell | Evaluate every `>>>` example in comments |
| `<localleader>h` | Haskell | Hoogle search for the signature under the cursor |
| `<localleader>r` / `<localleader>R` | Haskell | GHCi REPL for the package / for this file |
| `<localleader>r` | Common Lisp, Racket | Toggle the REPL window, starting it the first time |
| `<localleader>e` | Common Lisp, Racket | Evaluate the top-level form; in Visual mode, the selection |
| `<localleader>b` | Common Lisp | Evaluate the whole buffer |
| `<localleader>b` | Racket | Save, run the file as a module and enter its namespace |
| `<localleader>i` | Common Lisp, Racket | Interrupt (Ctrl-C); in sbcl, type `abort` to return to the top level |
| `<localleader>q` | Common Lisp, Racket | Quit the REPL |

Details: [languages](features/lang.md#common-lisp).

## Neovide

| Key | Action |
|---|---|
| `<C-=>` / `<C-+>` | Zoom in (scale × 1.1) |
| `<C-->` | Zoom out |
| `<C-0>` | Reset the zoom |
| `<C-S-v>` | Paste from the system clipboard (Normal, Insert, Visual, command line, terminal) |
