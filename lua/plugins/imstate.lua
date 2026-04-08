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
local fcitx_in_flight = false

local function update_caps_status()
  if not actual_caps_path then
    return
  end

  local f = io.open(actual_caps_path, "r")
  if f then
    local data = f:read("*a")
    f:close()
    caps_state = (data and data:find("1")) and "󰬈 CAPS" or ""
  end
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
      if res == "hangul" then
        im_state = "한"
      else
        im_state = (caps_state ~= "") and "EN" or "en"
      end
    end,
  })
end

local function start_kbd_check()
  local timer = uv.new_timer()
  if not timer then
    return false
  end

  timer:start(
    0,
    200,
    vim.schedule_wrap(function()
      update_caps_status()

      if has_fcitx5 then
        poll_fcitx_async()
      end
    end)
  )
  return true
end

if not _G._kbd_timer_started then
  _G._kbd_timer_started = start_kbd_check()
end

return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      if has_fcitx5 then
        table.insert(opts.sections.lualine_x, 1, {
          function()
            return im_state
          end,
          color = function()
            return { fg = im_state == "한" and "#ff9e64" or "#7aa2f7", gui = "bold" }
          end,
          padding = { left = 1, right = 1 },
        })
      end

      if actual_caps_path then
        table.insert(opts.sections.lualine_x, has_fcitx5 and 2 or 1, {
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
    end,
  },
}
