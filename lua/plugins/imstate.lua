local uv = vim.uv or vim.loop
local has_fcitx5 = vim.fn.executable("fcitx5-remote") == 1
local has_caps_path = vim.fn.glob("/sys/class/leds/input*::capslock/brightness") ~= ""

if not has_fcitx5 and not has_caps_path then
  return {}
end

local im_state = "EN"
local caps_state = ""

local function read_caps_status()
  if not has_caps_path then
    return ""
  end
  local handle = io.popen("cat /sys/class/leds/input*::capslock/brightness 2>/dev/null")
  if not handle then
    return ""
  end
  local result = handle:read("*a")
  handle:close()

  if result and result:find("1") then
    return "󰬈 CAPS"
  else
    return ""
  end
end

local function start_kbd_check()
  local timer = uv.new_timer()
  timer:start(
    0,
    50,
    vim.schedule_wrap(function()
      if has_fcitx5 then
        local f = io.popen("fcitx5-remote -n 2>/dev/null")
        if f then
          local res = f:read("*a"):gsub("%s+", "")
          f:close()
          im_state = (res == "hangul") and "한" or "EN"
        end
      end

      caps_state = read_caps_status()
    end)
  )
end

start_kbd_check()

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

      if has_caps_path then
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
