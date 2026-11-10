# Language servers

Rules that keep a language server off where it should not run, the line diagnostics it shows, and the Mason packages the configuration installs. The servers themselves are set up per language ([languages](lang.md)). Specs: `lua/plugins/lsp/`; code: `lua/features/lsp/`.

## Attach rules

Attach rules turn a language server off for generated or vendored subtrees.

### What it does

A rule matches a path prefix (`within`) or a path segment (`contains`), targets `clangd` unless it names other servers or all (`"*"`), and either detaches the client (`disable`) or hides its diagnostics (`diagnostics_off`). Rules are checked when a client attaches.

The rules live in `stdpath("data")/nvim-config/language_server_attach_rules.json`, outside every repository, and reload when that file is written:

```json
{ "rules": [ { "within": "/home/me/linux/drivers/gpu", "servers": ["clangd"], "action": "disable" } ] }
```

| Want to | Do |
|---|---|
| Turn clangd off for a directory | open a file in it, `<leader>cLd`, pick the directory |
| Pick the servers and the action | `<leader>cLa` |
| See why a server runs here | `<leader>cLl` |
| Turn every rule off for now | `<leader>cLt` (this session only) |
| Remove a rule | `<leader>cLe`, delete it from `rules`, `:w` |

Per-directory marker files (`.nvim-lsp-filter.json`) are read only with `markers_enabled = true` in the `setup()` of `features.lsp.attach_rules`; the spec does not set it.

### Keys and commands

No commands; keys: [keymaps](../keymaps.md#language-server-attach-rules).

### What it needs

Nothing beyond the servers. `:checkhealth features.lsp` checks the rules file and each enabled server's command.

### Systems

Linux, macOS and Windows alike.

## Line diagnostics

On `CursorHold` the line's diagnostics open in a float with their source, and close when the cursor leaves the line (`lua/plugins/lsp/diagnostics.lua`). Only namespaces still enabled for the buffer show, so what a `diagnostics_off` rule hides stays hidden. Inlay hints are off.

## Mason packages

Each file of `lua/plugins/lang/`, `formatting.lua`, `linting.lua` and `dap/core.lua` names the packages it needs, and `lua/plugins/lsp/mason.lua` the rest; Mason installs them beside LazyVim's defaults into `stdpath("data")/mason`. [Credits](../credits.md) lists every package with its license.

Some packages need a runtime on PATH to run (`lua/features/lsp/mason/runtime_requirements.lua`), and `:FeatureStatus` warns when an installed one lacks it:

| Runtime | Packages |
|---|---|
| `java` | `detekt`, `jdtls`, `kotlin-lsp`, `ktlint` |
| `elixir` | `elixir-ls`, `expert` |
| `erl` | `elp` |
| `julia` | `julia-lsp` |
| `node` | `js-debug-adapter` and every npm package |

Windows (`lua/features/lsp/mason/windows_install_gate.lua`): Mason skips a package whose runtime is missing, and for 7 days one whose install failed (`stdpath("state")/nvim-config/mason_install_failures.json`), so a hopeless build does not rerun every session. `:MasonInstall NAME` retries at once; installed packages stay. Servers pass the same gate: a held-back one gets `mason = false` and starts only from PATH. An unreadable failure record holds nothing back and is never overwritten; `:checkhealth features.lsp` names it.

### What it needs

The runtimes above; `:checkhealth mason` lists what Mason's installers need.

### Systems

| Part | Linux | macOS | Windows |
|---|---|---|---|
| Mason packages | yes; one with no build for the machine is reported as not supported | yes | yes, with the install gate |
