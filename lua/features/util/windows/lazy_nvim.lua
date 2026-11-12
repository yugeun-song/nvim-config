-- lazy.nvim on Windows, where starting a process and resolving runtimepath entries cost what they do not elsewhere.
-- lua/config/lazy.lua calls this on Windows only.
local M = {}

local function runtimepath()
  return vim.opt.rtp:get() --[[@as string[] ]]
end

-- :packadd resolves every 'runtimepath' entry to its full path, which costs about 20 ms more for each of matchit and
-- netrw once the plugins are on it. They load before lazy.setup instead, while it holds a few entries; lazy keeps
-- their directories on the runtimepath it resets, and the runtime's own stubs find them loaded.
---@return string[] # the directories they added, for lazy's performance.rtp.paths
function M.load_early_packs()
  local early_packs = {}
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

  return early_packs
end

-- lazy's update check starts git once per plugin right after startup (60 processes here), and Windows
-- holds the editor about 5 ms on each process it starts, so a terminal such as yazi's stutters for the first
-- seconds. The check, and the hourly one, wait instead until no key has come for 5 s outside a terminal, or
-- until Neovim has been without focus for a second.
-- The check always starts from the main loop, never from inside the focus autocmd: it waits on git (vim.wait),
-- Neovim takes other events meanwhile, and a focus event that arrives while a focus autocmd still runs is
-- dropped. Neovide loses and regains focus within 0.1 s as its window appears: run from that FocusLost, the
-- check swallowed the FocusGained after it, and Neovim stayed "unfocused" until the next change of focus.
function M.defer_update_checks()
  local IDLE_MS = 5000
  local UNFOCUSED_MS = 1000
  -- One namespace for every wait: the checks come one at a time, an hour apart.
  local ns = vim.api.nvim_create_namespace("lazy_update_check_when_idle")

  local function when_idle(fn)
    return function(...)
      local args, done, unfocused = { ... }, false, false
      local timer = assert(vim.uv.new_timer())
      local autocmds = {}
      local when_quiet

      local function run()
        if done then
          return
        end

        done = true
        vim.on_key(nil, ns)
        timer:close()
        for _, id in ipairs(autocmds) do
          pcall(vim.api.nvim_del_autocmd, id)
        end

        fn(unpack(args))
      end

      -- Both on the main loop, made once: a key restarts the timer with nothing new to allocate.
      local quiet = vim.schedule_wrap(function()
        if done then
          return
        end

        if vim.api.nvim_get_mode().mode:find("^t") then
          return when_quiet()
        end

        run()
      end)

      local left = vim.schedule_wrap(function()
        if unfocused then
          run()
        end
      end)

      -- Starting a running timer restarts it.
      when_quiet = function()
        timer:start(IDLE_MS, 0, quiet)
      end

      vim.on_key(function()
        if not done then
          when_quiet()
        end
      end, ns)

      autocmds = {
        vim.api.nvim_create_autocmd("FocusLost", {
          callback = function()
            unfocused = true
            timer:start(UNFOCUSED_MS, 0, left)
          end,
        }),
        vim.api.nvim_create_autocmd("FocusGained", {
          callback = function()
            unfocused = false
            when_quiet()
          end,
        }),
      }

      when_quiet()
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

return M
