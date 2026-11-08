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

  -- The first start after :ManagedPathsReset: say what it removed once the UI is up.
  pcall(function()
    require("features.maintenance.stored_data_paths").announce_report()
  end)
end

vim.opt.rtp:prepend(lazypath)

-- Windows: :packadd resolves every 'runtimepath' entry to its full path, which costs about 20 ms more for each
-- of matchit and netrw once the plugins are on it. They load here instead, while it holds a few entries; lazy
-- keeps their directories on the runtimepath it resets, and the runtime's own stubs find them loaded.
local early_packs = {}

local function runtimepath()
  return vim.opt.rtp:get() --[[@as string[] ]]
end

if vim.fn.has("win32") == 1 then
  local before = {}

  for _, dir in ipairs(runtimepath()) do
    before[dir] = true
  end

  vim.cmd("silent! packadd matchit | silent! packadd netrw")
  for _, dir in ipairs(runtimepath()) do
    if not before[dir] then
      early_packs[#early_packs + 1] = dir
    end
  end
end

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

-- Windows: lazy's update check starts git once per plugin right after startup (60 processes here), and Windows
-- holds the editor about 5 ms on each process it starts, so a terminal such as yazi's stutters for the first
-- seconds. The check, and the hourly one, wait instead until no key has come for 5 s outside a terminal, or
-- until Neovim loses focus.
if vim.fn.has("win32") == 1 then
  local IDLE_MS = 5000

  local function when_idle(fn)
    return function(...)
      local args, done = { ... }, false
      local ns = vim.api.nvim_create_namespace("")
      local timer = assert(vim.uv.new_timer())
      local fire

      local function run()
        if done then
          return
        end

        done = true
        vim.on_key(nil, ns)
        timer:close()
        fn(unpack(args))
      end

      local function arm()
        timer:start(IDLE_MS, 0, vim.schedule_wrap(fire))
      end

      fire = function()
        if done then
          return
        end

        if vim.api.nvim_get_mode().mode:find("^t") then
          return arm()
        end

        run()
      end

      vim.on_key(function()
        if not done then
          timer:stop()
          arm()
        end
      end, ns)

      vim.api.nvim_create_autocmd("FocusLost", { once = true, callback = run })
      arm()
    end
  end

  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    once = true,
    -- Runs after lazy's own VeryLazy handler, before the 10 ms timer it sets to call checker.start.
    callback = function()
      local checker = require("lazy.manage.checker")

      checker.start = when_idle(checker.start)
      checker.check = when_idle(checker.check)
    end,
  })
end
