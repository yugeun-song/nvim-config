local POLL_INTERVAL_MS = 2000

local minifiles_dirty = {}

local function checktime()
  if vim.fn.getcmdwintype() ~= "" or vim.bo.buftype == "nofile" then
    return
  end
  pcall(vim.cmd.checktime)
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

return {
  "fs_refresh",
  virtual = true,
  config = function()
    local group = vim.api.nvim_create_augroup("FsRefresh", { clear = true })

    vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "CursorHoldI" }, {
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

    local timer = (vim.uv or vim.loop).new_timer()
    timer:start(
      POLL_INTERVAL_MS,
      POLL_INTERVAL_MS,
      vim.schedule_wrap(function()
        checktime()
        if vim.fn.mode() ~= "n" or next(minifiles_dirty) ~= nil then
          return
        end
        local mf = minifiles_if_open()
        if mf then
          minifiles_refresh(mf)
        end
      end)
    )

    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      callback = function()
        timer:stop()
        if not timer:is_closing() then
          timer:close()
        end
      end,
      desc = "Stop the fs refresh poll timer",
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
  end,
}
