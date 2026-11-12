-- The IME (한/EN) and Caps Lock indicators of the statusline, read the way each system allows
-- (lua/features/editor/korean_input/backends.lua) and paused while Neovim has no focus.
local M = {}

local uv = vim.uv

local backends = require("features.editor.korean_input.backends")
local sources = backends.indicators()
local im, caps_path, caps_watch = sources.im, sources.caps, sources.caps_watch
local both = sources.watch

-- im is "" until the input method answers.
local state = { im = "", caps = "" }

local function set(key, value)
  if state[key] ~= value then
    state[key] = value
    vim.g[key == "im" and "im_state" or "caps_state"] = value
  end
end

local function set_im(hangul)
  if hangul == nil then
    set("im", "")
  elseif hangul then
    set("im", "한")
  else
    set("im", state.caps ~= "" and "EN" or "en")
  end
end

local function set_caps(on)
  set("caps", on and "󰬈 CAPS" or "")
  if state.im == "en" or state.im == "EN" then
    set_im(false)
  end
end

local caps_busy, im_busy, finding = false, false, false

-- A replugged keyboard gets another LED node (inputN): look it up again.
local function find_caps()
  if finding then
    return
  end

  finding = true
  vim.schedule(function()
    finding = false
    caps_path = backends.caps_led()
    if not caps_path then
      set_caps(false)
    end
  end)
end

local function read_caps()
  if caps_busy then
    return
  end

  if not caps_path then
    return find_caps()
  end

  caps_busy = true
  uv.fs_open(caps_path, "r", 438, function(err, fd)
    if err or not fd then
      caps_busy = false
      caps_path = nil
      find_caps()

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

-- A read overlapping a switch may report the old mode: none starts during one, and an overlapping one reruns.
local switching, generation = 0, 0

local function read_im()
  if im_busy or not im or switching > 0 then
    return
  end

  im_busy = true
  local started = generation

  local function on_exit(res)
    im_busy = false
    if started ~= generation then
      return read_im()
    end

    if res.code == 0 then
      set_im(im.hangul(res.stdout or ""))
    else
      set_im(nil)
    end
  end

  local ok = pcall(vim.system, im.cmd, { text = true }, vim.schedule_wrap(on_exit))

  if not ok then
    im_busy = false
    set_im(nil)
  end
end

function M.switch_started()
  switching = switching + 1
  generation = generation + 1
end

function M.switch_finished()
  switching = math.max(switching - 1, 0)
  generation = generation + 1
  read_im()
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

-- Windows: one long-lived windows_ime_helper for both, started once; focus changes pause and resume it through its
-- stdin instead of ending and starting a process.
local last_pair

local function on_pair(data)
  local pair = data:match("([01][01])%s*$")

  if pair and pair ~= last_pair then
    last_pair = pair
    vim.schedule(function()
      set_caps(pair:sub(1, 1) == "1")
      set_im(pair:sub(2, 2) == "1")
    end)
  end
end

-- Whether Neovim has the focus, as far as the indicators were told.
local active, awaited = false, false

local function watch_both()
  if not both then
    return
  end

  local ime_helper = require("features.util.windows.ime_helper")

  if ime_helper.send("r") or ime_helper.watch(on_pair) or awaited then
    return
  end

  -- Still being built (the first start, or the first after its source changed): watched once it lands.
  awaited = true
  ime_helper.on_ready(function()
    if active then
      watch_both()
    end
  end)
end

local has_caps = caps_path ~= nil or caps_watch ~= nil or both ~= nil
local has_im = im ~= nil or both ~= nil

function M.start()
  if not has_im and not has_caps then
    return
  end

  vim.g.im_state, vim.g.caps_state = state.im, state.caps
  local timers = {}

  if caps_path then
    timers[#timers + 1] = { assert(uv.new_timer()), 200, read_caps }
  end

  if im then
    timers[#timers + 1] = { assert(uv.new_timer()), 1000, vim.schedule_wrap(read_im) }
  end

  local function run()
    active = true
    for _, t in ipairs(timers) do
      t[1]:start(0, t[2], t[3])
    end

    if caps_watch then
      watch_caps()
    end

    if both then
      watch_both()
    end
  end

  local function pause()
    active = false
    for _, t in ipairs(timers) do
      t[1]:stop()
    end

    if both then
      require("features.util.windows.ime_helper").send("p")
    elseif watcher then
      watcher:kill("sigterm")
      watcher = nil
    end
  end

  local group = vim.api.nvim_create_augroup("korean_input_indicator", { clear = true })

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

-- The lualine components, Caps Lock first; none for what this system cannot report.
function M.statusline_components()
  local components = {}

  if has_caps then
    components[#components + 1] = {
      function()
        return state.caps
      end,
      color = { fg = "#f7768e", gui = "bold" },
      cond = function()
        return state.caps ~= ""
      end,
      padding = { left = 1, right = 1 },
    }
  end

  if has_im then
    components[#components + 1] = {
      function()
        return state.im
      end,
      color = function()
        return { fg = state.im == "한" and "#ff9e64" or "#7aa2f7", gui = "bold" }
      end,
      cond = function()
        return state.im ~= ""
      end,
      padding = { left = 1, right = 1 },
    }
  end

  return components
end

return M
