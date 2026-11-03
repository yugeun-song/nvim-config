local uv = vim.uv

local has_fcitx5 = vim.fn.executable("fcitx5-remote") == 1
local caps_path = vim.fn.glob("/sys/class/leds/input*::capslock/brightness", true, true)[1]

local state = { im = "en", caps = "" }

local function set(key, value)
  if state[key] ~= value then
    state[key] = value
    vim.g[key == "im" and "im_state" or "caps_state"] = value
  end
end

local function set_im(engine)
  if engine == "hangul" then
    set("im", "한")
  else
    set("im", state.caps ~= "" and "EN" or "en")
  end
end

local caps_busy, fcitx_busy = false, false

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
          set("caps", (data and data:find("1")) and "󰬈 CAPS" or "")
          if has_fcitx5 and state.im ~= "한" then
            set_im(nil)
          end
        end)
      end
    end)
  end)
end

local function read_fcitx()
  if fcitx_busy then
    return
  end
  fcitx_busy = true
  local ok = pcall(vim.system, { "fcitx5-remote", "-n" }, { text = true }, function(res)
    fcitx_busy = false
    if res.code == 0 then
      vim.schedule(function()
        set_im((res.stdout or ""):gsub("%s+", ""))
      end)
    end
  end)
  if not ok then
    fcitx_busy = false
  end
end

local function start()
  vim.g.im_state, vim.g.caps_state = state.im, state.caps
  local timers = {}
  if caps_path then
    timers[#timers + 1] = { assert(uv.new_timer()), 200, read_caps }
  end
  if has_fcitx5 then
    timers[#timers + 1] = { assert(uv.new_timer()), 1000, vim.schedule_wrap(read_fcitx) }
  end
  local function run()
    for _, t in ipairs(timers) do
      t[1]:start(0, t[2], t[3])
    end
  end
  local group = vim.api.nvim_create_augroup("IMState", { clear = true })
  vim.api.nvim_create_autocmd("FocusLost", {
    group = group,
    callback = function()
      for _, t in ipairs(timers) do
        t[1]:stop()
      end
    end,
  })
  vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = run })
  if has_fcitx5 then
    vim.api.nvim_create_autocmd({ "InsertEnter", "InsertLeave", "CursorHold", "CursorHoldI" }, {
      group = group,
      callback = read_fcitx,
    })
  end
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, t in ipairs(timers) do
        t[1]:close()
      end
    end,
  })
  run()
end

if not has_fcitx5 and not caps_path then
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
      if caps_path then
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
      if has_fcitx5 then
        table.insert(opts.sections.lualine_x, caps_path and 2 or 1, {
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
