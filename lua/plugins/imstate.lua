local uv = vim.uv

local sources = require("config.ime").indicators()
local im, caps_path, caps_watch = sources.im, sources.caps, sources.caps_watch

local state = { im = "en", caps = "" }

local function set(key, value)
  if state[key] ~= value then
    state[key] = value
    vim.g[key == "im" and "im_state" or "caps_state"] = value
  end
end

local function set_im(hangul)
  if hangul then
    set("im", "한")
  else
    set("im", state.caps ~= "" and "EN" or "en")
  end
end

local function set_caps(on)
  set("caps", on and "󰬈 CAPS" or "")
  if im and state.im ~= "한" then
    set_im(false)
  end
end

local caps_busy, im_busy = false, false

local function read_caps()
  if caps_busy then
    return
  end

  caps_busy = true
  uv.fs_open(caps_path, "r", 438, function(err, fd)
    if err or not fd then
      caps_busy = false

      return
    end

    uv.fs_read(fd, 8, 0, function(rerr, data)
      uv.fs_close(fd)
      caps_busy = false
      if not rerr then
        vim.schedule(function()
          set_caps(data ~= nil and data:find("1") ~= nil)
        end)
      end
    end)
  end)
end

local function read_im()
  if im_busy or not im then
    return
  end

  im_busy = true
  local ok = pcall(vim.system, im.cmd, { text = true }, function(res)
    im_busy = false
    if res.code == 0 then
      vim.schedule(function()
        set_im(im.hangul(res.stdout or ""))
      end)
    end
  end)

  if not ok then
    im_busy = false
  end
end

local watcher = nil

local function watch_caps()
  if watcher or not caps_watch then
    return
  end

  local last, proc = nil, nil
  local ok = pcall(function()
    proc = vim.system(caps_watch, {
      stdout = function(_, data)
        local on = data and data:match("([01])%s*$")

        if on and on ~= last then
          last = on
          vim.schedule(function()
            set_caps(on == "1")
          end)
        end
      end,
    }, function()
      if watcher == proc then
        watcher = nil
      end
    end)
  end)

  watcher = ok and proc or nil
end

local function start()
  vim.g.im_state, vim.g.caps_state = state.im, state.caps
  local timers = {}

  if caps_path then
    timers[#timers + 1] = { assert(uv.new_timer()), 200, read_caps }
  end

  if im then
    timers[#timers + 1] = { assert(uv.new_timer()), 1000, vim.schedule_wrap(read_im) }
  end

  local function run()
    for _, t in ipairs(timers) do
      t[1]:start(0, t[2], t[3])
    end

    if caps_watch then
      watch_caps()
    end
  end

  local function pause()
    for _, t in ipairs(timers) do
      t[1]:stop()
    end

    if watcher then
      watcher:kill("sigterm")
      watcher = nil
    end
  end

  local group = vim.api.nvim_create_augroup("IMState", { clear = true })

  vim.api.nvim_create_autocmd("FocusLost", { group = group, callback = pause })
  vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = run })
  if im then
    vim.api.nvim_create_autocmd({ "InsertEnter", "InsertLeave", "CursorHold", "CursorHoldI" }, {
      group = group,
      callback = read_im,
    })
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      pause()
      for _, t in ipairs(timers) do
        if not t[1]:is_closing() then
          t[1]:close()
        end
      end
    end,
  })

  run()
end

local has_caps = caps_path ~= nil or caps_watch ~= nil

if not im and not has_caps then
  return {}
end

return {
  {
    "imstate",
    virtual = true,
    event = "VeryLazy",
    config = start,
  },
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      if has_caps then
        table.insert(opts.sections.lualine_x, 1, {
          function()
            return state.caps
          end,
          color = { fg = "#f7768e", gui = "bold" },
          cond = function()
            return state.caps ~= ""
          end,
          padding = { left = 1, right = 1 },
        })
      end

      if im then
        table.insert(opts.sections.lualine_x, has_caps and 2 or 1, {
          function()
            return state.im
          end,
          color = function()
            return { fg = state.im == "한" and "#ff9e64" or "#7aa2f7", gui = "bold" }
          end,
          padding = { left = 1, right = 1 },
        })
      end
    end,
  },
}
