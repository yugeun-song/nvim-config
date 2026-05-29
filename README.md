# nvim-config

Neovim configuration based on LazyVim, configured for Linux kernel development.

## Structure
- **lua/config/**: Core settings (options, keymaps, autocmds).
- **lua/plugins/**: Plugin-specific configurations (clangd, cscope, imstate, etc.).
- **stylua.toml**: Lua code formatting rules.

## Features
- **Kernel Coding Style**: 8-char tabs and noexpandtab for C/C++ files; auto-formatting disabled.
- **Dynamic clangd Workers**: Auto-calculates `-j` flag based on 50% of available CPU threads.
- **Input Status**: Displays Fcitx5 (Hangul/English) and CapsLock state on lualine.
- **Cscope/Telescope**: Cscope navigation mappings integrated with Telescope.
- **File Explorer**: mini.files for yazi-style Miller-column navigation (`<leader>fm`/`<leader>fM` to open, `<CR>` to open/enter, `gc` to set cwd).

## Installation
Simply clone the repository into your preferred workspace. For reference, this configuration is currently managed via a symbolic link from the workspace to the Neovim config directory:

```zsh
# Example of the current setup
git clone https://github.com/yugeun-song/nvim-config.git ~/workspace/nvim-config
ln -s ~/workspace/nvim-config ~/.config/nvim
