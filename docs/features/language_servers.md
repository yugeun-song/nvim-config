# Language servers

Attach rules turn a language server off for generated or vendored subtrees. Spec: `lua/plugins/language_servers/attach_rules.lua`; code: `lua/features/language_servers/attach_rules/`. The servers themselves are set up per language ([languages](languages.md)) and installed by Mason ([external programs](external_programs.md)).

## What it does

A rule matches a path prefix (`within`) or a path segment (`contains`), targets `clangd` unless it names other servers or all (`"*"`), and either detaches the client (`disable`) or hides its diagnostics (`diagnostics_off`). Rules are checked when a client attaches.

The rules live in `stdpath("data")/nvim-config/language_server_attach_rules.json`, outside every repository, and reload when that file is written:

```json
{ "rules": [ { "within": "/home/me/linux/drivers/gpu", "servers": ["clangd"], "action": "disable" } ] }
```

| Want to | Do |
|---|---|
| Turn clangd off for a directory | open a file in it, `<leader>cFd`, pick the directory |
| Pick the servers and the action | `<leader>cFa` |
| See why a server runs here | `<leader>cFl` |
| Turn every rule off for now | `<leader>cFt` (this session only) |
| Remove a rule | `<leader>cFe`, delete it from `rules`, `:w` |

Per-directory marker files (`.nvim-lsp-filter.json`) are read only with `markers_enabled = true` in the `setup()` of `features.language_servers.attach_rules`; the spec does not set it.

## Keys and commands

No commands; keys: [keymaps](../keymaps.md#language-server-attach-rules).

## What it needs

Nothing beyond the servers. `:checkhealth features.language_servers` checks the rules file and each enabled server's command.

## Systems

Linux, macOS and Windows alike.
