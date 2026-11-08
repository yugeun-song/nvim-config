-- Modified from https://github.com/LazyVim/starter (Apache-2.0). See THIRD-PARTY-NOTICES.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })

  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})

    vim.fn.getchar()
    os.exit(1)
  end
end

vim.opt.rtp:prepend(lazypath)

-- Windows only: matchit and netrw before the runtimepath fills, lazy's update checks when idle
-- (lua/features/windows_platform/lazy_nvim_on_windows.lua).
local on_windows = vim.fn.has("win32") == 1 and require("features.windows_platform.lazy_nvim_on_windows") or nil
local early_packs = on_windows and on_windows.load_early_packs() or {}

require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- One directory per purpose; lazy.nvim imports a directory's files, not its subdirectories.
    { import = "plugins.appearance" },
    { import = "plugins.editing" },
    { import = "plugins.help" },
    { import = "plugins.input_method" },
    { import = "plugins.languages" },
    { import = "plugins.language_servers" },
    { import = "plugins.debugging" },
    { import = "plugins.external_programs" },
    { import = "plugins.maintenance" },
    { import = "plugins.integrations" },
  },
  defaults = {
    -- Every plugin of this configuration loads on its own trigger (event, ft, cmd, keys); one without a trigger
    -- would never load, so each states when it is needed. LazyVim's own plugins carry theirs.
    lazy = true,
    version = false,
  },
  install = { colorscheme = { "gruvbox-material", "tokyonight" } },
  checker = {
    enabled = true,
    notify = false,
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
      paths = early_packs,
    },
  },
})

if on_windows then
  on_windows.defer_update_checks()
end
