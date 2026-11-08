-- Buffers and file explorers follow changes made outside Neovim: checktime on the events LazyVim's focus-based
-- check misses, a note of what was reloaded, mini.files kept in step with the disk. :FsRefresh, <leader>uR.
local M = {}

local POLL_INTERVAL_MS = 2000

local minifiles_dirty = {}

-- Buffers without unsaved changes only, and only in Normal mode: a changed file under unsaved edits asks (W12),
-- and a question popping up unasked takes the next key as its answer ("l" loads the file over the edits). Those are
-- left to LazyVim's check on FocusGained, when the user is looking, and to :checktime.
local function checktime()
  if vim.fn.getcmdwintype() ~= "" or vim.api.nvim_get_mode().mode ~= "n" then
    return
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(buf)
      and vim.bo[buf].buftype == ""
      and not vim.bo[buf].modified
      and vim.api.nvim_buf_get_name(buf) ~= ""
    then
      pcall(vim.cmd.checktime, buf)
    end
  end
end

local function minifiles_if_open()
  local mf = package.loaded["mini.files"]

  if mf == nil then
    return nil
  end

  local ok, state = pcall(mf.get_explorer_state)

  if not ok or state == nil then
    return nil
  end

  return mf
end

local function minifiles_refresh(mf)
  pcall(mf.refresh, { content = { sort = mf.default_sort } })
end

local function snacks_explorer_refresh()
  if package.loaded["snacks"] == nil then
    return 0
  end

  local ok, count = pcall(function()
    local pickers = Snacks.picker.get({ source = "explorer", tab = false })
    local Tree = require("snacks.explorer.tree")
    local Actions = require("snacks.explorer.actions")

    for _, picker in ipairs(pickers) do
      Tree:refresh(picker:cwd())
      Actions.update(picker, { refresh = true })
    end

    return #pickers
  end)

  if ok then
    return count
  end

  return 0
end

function M.setup()
  local group = vim.api.nvim_create_augroup("reload_on_external_change", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold" }, {
    group = group,
    callback = checktime,
    desc = "Check for external file changes on events LazyVim's focus-based checktime misses",
  })

  local reloaded = {}
  local flush_scheduled = false

  vim.api.nvim_create_autocmd("FileChangedShellPost", {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].modified then
        return
      end

      table.insert(reloaded, vim.fn.fnamemodify(args.file, ":~:."))
      if flush_scheduled then
        return
      end

      flush_scheduled = true
      vim.defer_fn(function()
        local msg = #reloaded == 1 and "Reloaded from disk: " .. reloaded[1]
          or ("Reloaded %d buffers from disk"):format(#reloaded)

        reloaded = {}
        flush_scheduled = false
        vim.notify(msg, vim.log.levels.INFO)
      end, 100)
    end,
    desc = "Notify when buffers are reloaded after an external change",
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    pattern = "minifiles://*",
    callback = function(args)
      minifiles_dirty[args.buf] = true
    end,
    desc = "Mark mini.files buffers holding pending manual edits",
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MiniFilesBufferUpdate",
    callback = function(args)
      local buf = args.data.buf_id

      vim.defer_fn(function()
        minifiles_dirty[buf] = nil
      end, 100)
    end,
    desc = "Clear the pending-edit mark after mini.files rewrites a buffer",
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    pattern = "minifiles://*",
    callback = function(args)
      minifiles_dirty[args.buf] = nil
    end,
    desc = "Drop pending-edit marks of wiped mini.files buffers",
  })

  local watchers, pending = {}, false

  local function refresh_soon()
    if pending then
      return
    end

    pending = true
    vim.defer_fn(function()
      pending = false
      local mf = minifiles_if_open()

      if mf and vim.fn.mode() == "n" and next(minifiles_dirty) == nil then
        minifiles_refresh(mf)
      end
    end, 100)
  end

  local function sync_watchers()
    local mf = minifiles_if_open()
    local wanted = {}

    if mf then
      local ok, state = pcall(mf.get_explorer_state)

      for _, path in ipairs(ok and state and state.branch or {}) do
        if vim.fn.isdirectory(path) == 1 then
          wanted[path] = true
        end
      end
    end

    for path, handle in pairs(watchers) do
      if not wanted[path] then
        handle:close()
        watchers[path] = nil
      end
    end

    for path in pairs(wanted) do
      if not watchers[path] then
        local handle = vim.uv.new_fs_event()

        if handle and handle:start(path, {}, vim.schedule_wrap(refresh_soon)) == 0 then
          watchers[path] = handle
        elseif handle then
          handle:close()
        end
      end
    end
  end

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "MiniFilesExplorerOpen", "MiniFilesBufferUpdate", "MiniFilesExplorerClose" },
    callback = vim.schedule_wrap(sync_watchers),
    desc = "Watch the directories an open mini.files shows",
  })

  local timer = assert(vim.uv.new_timer())

  local function poll()
    timer:start(POLL_INTERVAL_MS, POLL_INTERVAL_MS, vim.schedule_wrap(checktime))
  end

  poll()
  vim.api.nvim_create_autocmd("FocusLost", {
    group = group,
    callback = function()
      timer:stop()
    end,
    desc = "Pause the checktime poll while unfocused",
  })

  vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = poll, desc = "Resume the checktime poll" })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if not timer:is_closing() then
        timer:close()
      end

      for _, handle in pairs(watchers) do
        handle:close()
      end

      watchers = {}
    end,
    desc = "Stop the fs refresh timer and watchers",
  })

  vim.api.nvim_create_user_command("FsRefresh", function()
    pcall(vim.cmd.checktime)
    local refreshed = { "buffers" }

    if snacks_explorer_refresh() > 0 then
      table.insert(refreshed, "explorer")
    end

    local mf = minifiles_if_open()

    if mf then
      minifiles_refresh(mf)
      table.insert(refreshed, "mini.files")
    end

    vim.notify("Refreshed " .. table.concat(refreshed, ", "), vim.log.levels.INFO)
  end, { desc = "Reload buffers and refresh open file explorers from disk" })

  vim.keymap.set("n", "<leader>uR", "<cmd>FsRefresh<cr>", { desc = "Refresh files & explorers" })
end

return M
