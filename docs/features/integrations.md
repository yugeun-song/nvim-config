# Integrations

Discord Rich Presence. Spec: `lua/plugins/integrations/discord_rich_presence.lua`; code: `lua/features/integrations/discord_rich_presence.lua`.

## What it does

Rich Presence over Discord's IPC socket (a named pipe on Windows), written from the public protocol, with no plugin. On by default from `VeryLazy`, it shows "Editing in Neovim" and the elapsed time; no file or workspace names. It finds the desktop client's socket, and those of its Snap and Flatpak builds and of Vesktop's Flatpak.

It borrows the public application ID and `neovim` art of [presence.nvim](https://github.com/andweeb/presence.nvim). `vim.g.discord_rich_presence_client_id`, set before the first screen, uses an application of one's own, and `vim.g.discord_rich_presence_image` names its art.

## Keys and commands

| Command | Does |
|---|---|
| `:DiscordRpcToggle` | Turn it on or off (`<leader>uP`) |
| `:DiscordRpcStatus` | Say whether it runs and its connection state |

## What it needs

The Discord desktop client (or Vesktop), running.

## Systems

Linux, macOS and Windows. Under WSL the Windows client's pipe is not reachable.
