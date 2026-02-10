local im_state = "EN"
local caps_state = ""
local uv = vim.uv or vim.loop

local function read_caps_status()
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
      local f = io.popen("fcitx5-remote -n 2>/dev/null")
      if f then
        local res = f:read("*a"):gsub("%s+", "")
        f:close()
        im_state = (res == "hangul") and "한" or "EN"
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
      table.insert(opts.sections.lualine_x, 1, {
        function()
          return im_state
        end,
        color = function()
          return { fg = im_state == "한" and "#ff9e64" or "#7aa2f7", gui = "bold" }
        end,
        padding = { left = 1, right = 1 },
      })

      table.insert(opts.sections.lualine_x, 2, {
        function()
          return caps_state
        end,
        color = { fg = "#f7768e", gui = "bold" },
        cond = function()
          return caps_state ~= ""
        end,
        padding = { left = 1, right = 1 },
      })
    end,
  },
}
