local uv = vim.uv or vim.loop
if not uv then
  return {}
end

local has_fcitx5 = vim.fn.executable("fcitx5-remote") == 1

local caps_paths = vim.fn.glob("/sys/class/leds/input*::capslock/brightness", true, true)
local actual_caps_path = caps_paths and caps_paths[1] or nil

if not has_fcitx5 and not actual_caps_path then
  return {}
end

local im_state = "en"
local caps_state = ""
local caps_in_flight = false
local fcitx_in_flight = false

local function set_im_state(res)
  if res == "hangul" then
    im_state = "한"
  else
    im_state = (caps_state ~= "") and "EN" or "en"
  end
  vim.g.im_state = im_state
end

local function set_caps_state(data)
  caps_state = (data and data:find("1")) and "󰬈 CAPS" or ""
  vim.g.caps_state = caps_state
  if has_fcitx5 and im_state ~= "한" then
    set_im_state(nil)
  end
end

local function update_caps_status()
  if not actual_caps_path or caps_in_flight then
    return
  end
  caps_in_flight = true

  uv.fs_open(actual_caps_path, "r", 438, function(err, fd)
    if err or not fd then
      caps_in_flight = false
      return
    end
    uv.fs_read(fd, 8, 0, function(rerr, data)
      uv.fs_close(fd)
      caps_in_flight = false
      if not rerr then
        vim.schedule(function()
          set_caps_state(data)
        end)
      end
    end)
  end)
end

local function poll_fcitx_async()
  if fcitx_in_flight then
    return
  end
  fcitx_in_flight = true

  local stdout_lines = {}
  vim.fn.jobstart({ "fcitx5-remote", "-n" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        stdout_lines = data
      end
    end,
    on_exit = function(_, code)
      fcitx_in_flight = false
      if code ~= 0 then
        return
      end
      local res = table.concat(stdout_lines, ""):gsub("%s+", "")
      set_im_state(res)
    end,
  })
end

local function start_kbd_check()
  if actual_caps_path then
    local timer = uv.new_timer()
    if not timer then
      return false
    end
    timer:start(0, 200, update_caps_status)
  end

  if has_fcitx5 then
    local timer = uv.new_timer()
    if not timer then
      return false
    end
    timer:start(0, 1000, vim.schedule_wrap(poll_fcitx_async))
    vim.api.nvim_create_autocmd({ "InsertEnter", "InsertLeave", "FocusGained", "CursorHold", "CursorHoldI" }, {
      group = vim.api.nvim_create_augroup("IMState", { clear = true }),
      callback = vim.schedule_wrap(poll_fcitx_async),
    })
  end
  return true
end

if not _G._kbd_timer_started then
  _G._kbd_timer_started = start_kbd_check()
end

return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      if actual_caps_path then
        table.insert(opts.sections.lualine_x, 1, {
          function()
            return caps_state
          end,
          color = { fg = "#f7768e", gui = "bold" },
          cond = function()
            return caps_state ~= ""
          end,
          padding = { left = 1, right = 1 },
        })
      end

      if has_fcitx5 then
        table.insert(opts.sections.lualine_x, actual_caps_path and 2 or 1, {
          function()
            return im_state
          end,
          color = function()
            return { fg = im_state == "한" and "#ff9e64" or "#7aa2f7", gui = "bold" }
          end,
          padding = { left = 1, right = 1 },
        })
      end
    end,
  },
}
