local M = {}

local uv = vim.uv or vim.loop

local config = {
  enabled = true,
  timeout = 1600,
  maxkeys = 5,
  separator = "   ",
  pad_x = 3,
  margin_right = 2,
  margin_bottom = 2,
  zindex = 250,
  border = "rounded",
  excluded_modes = {},
  color_sources = {
    "String",
    "Function",
    "Keyword",
    "Type",
    "Number",
    "Constant",
    "Special",
    "Identifier",
    "DiagnosticInfo",
    "DiagnosticWarn",
  },
  bold = true,
  im_indicator = true,
  kitty_keyboard = "auto",
}

local MOD_NAME = {
  C = "Ctrl",
  A = "Alt",
  M = "Alt",
  S = "Shift",
  D = "Cmd",
  T = "Ctrl+Alt",
}

local SPECIAL_LABEL = {
  Esc = "Esc",
  CR = "Enter",
  Enter = "Enter",
  Tab = "Tab",
  BS = "Back",
  Space = "Space",
  Up = "↑",
  Down = "↓",
  Left = "←",
  Right = "→",
  Del = "Del",
  Home = "Home",
  End = "End",
  PageUp = "PgUp",
  PageDown = "PgDn",
  Insert = "Ins",
  F1 = "F1",
  F2 = "F2",
  F3 = "F3",
  F4 = "F4",
  F5 = "F5",
  F6 = "F6",
  F7 = "F7",
  F8 = "F8",
  F9 = "F9",
  F10 = "F10",
  F11 = "F11",
  F12 = "F12",
}

local state = {
  ns = nil,
  buf = nil,
  win = nil,
  keys = {},
  timer = nil,
  last_color = 0,
}

local color_count = 0

local function parse_key(seq)
  local mods = {}
  local main = seq
  if seq:sub(1, 1) == "<" and seq:sub(-1) == ">" then
    local inner = seq:sub(2, -2)
    while true do
      local m, rest = inner:match("^([CASMD])%-(.+)$")
      if not m then
        break
      end
      table.insert(mods, m)
      inner = rest
    end
    main = inner
  end
  main = SPECIAL_LABEL[main] or main
  if #main == 1 then
    main = main:upper()
  end
  return mods, main
end

local function build_label(mods, main)
  if #mods == 0 then
    return main
  end
  local parts = {}
  for _, m in ipairs(mods) do
    table.insert(parts, MOD_NAME[m] or m)
  end
  return table.concat(parts, " + ") .. " + " .. main
end

local function pick_color()
  if color_count <= 1 then
    return 1
  end
  local idx = math.random(color_count)
  if idx == state.last_color then
    idx = (idx % color_count) + 1
  end
  state.last_color = idx
  return idx
end

local function stop_timer()
  if state.timer then
    pcall(function()
      state.timer:stop()
    end)
    pcall(function()
      state.timer:close()
    end)
    state.timer = nil
  end
end

local function arm_timer()
  stop_timer()
  local t = uv.new_timer()
  state.timer = t
  t:start(
    config.timeout,
    0,
    vim.schedule_wrap(function()
      M._wipe()
    end)
  )
end

local function close_window()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
end

function M._wipe()
  state.keys = {}
  close_window()
  stop_timer()
end

local function ensure_buf()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].bufhidden = "wipe"
end

local function place_window(inner_w)
  local inner_h = 1
  local outer_w = inner_w + 2
  local outer_h = inner_h + 2
  local col = math.max(0, vim.o.columns - config.margin_right - outer_w)
  local row = math.max(0, vim.o.lines - config.margin_bottom - outer_h)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_set_config, state.win, {
      relative = "editor",
      row = row,
      col = col,
      width = inner_w,
      height = inner_h,
    })
  else
    ensure_buf()
    state.win = vim.api.nvim_open_win(state.buf, false, {
      relative = "editor",
      row = row,
      col = col,
      width = inner_w,
      height = inner_h,
      focusable = false,
      style = "minimal",
      border = config.border,
      noautocmd = true,
      zindex = config.zindex,
    })
    pcall(
      vim.api.nvim_set_option_value,
      "winhighlight",
      "NormalFloat:ShowKeysCap,FloatBorder:ShowKeysCapBorder",
      { win = state.win }
    )
  end
end

local function render()
  if #state.keys == 0 then
    close_window()
    return
  end
  ensure_buf()

  local labels, spans = {}, {}
  local pos = 0
  for i, k in ipairs(state.keys) do
    if i > 1 then
      pos = pos + #config.separator
    end
    local s = pos
    pos = pos + #k.label
    table.insert(labels, k.label)
    table.insert(spans, { s = s, e = pos, color = k.color })
  end
  local text = table.concat(labels, config.separator)
  local pad = string.rep(" ", config.pad_x)

  local indicator = ""
  if config.im_indicator and vim.g.im_state == "한" then
    indicator = "한 "
  end
  local indicator_bytes = #indicator

  local line = pad .. indicator .. text .. pad

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { line })
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, state.ns, 0, -1)

  if indicator_bytes > 0 then
    pcall(vim.api.nvim_buf_set_extmark, state.buf, state.ns, 0, config.pad_x, {
      end_row = 0,
      end_col = config.pad_x + indicator_bytes,
      hl_group = "ShowKeysMod",
      priority = 100,
    })
  end

  local off = config.pad_x + indicator_bytes
  for _, sp in ipairs(spans) do
    pcall(vim.api.nvim_buf_set_extmark, state.buf, state.ns, 0, off + sp.s, {
      end_row = 0,
      end_col = off + sp.e,
      hl_group = "ShowKeysColor" .. sp.color,
      priority = 200,
    })
  end

  local inner_w = vim.fn.strdisplaywidth(line)
  if inner_w < 3 then
    inner_w = 3
  end
  place_window(inner_w)
end

local function push_key(label)
  table.insert(state.keys, { label = label, color = pick_color() })
  while #state.keys > config.maxkeys do
    table.remove(state.keys, 1)
  end
  render()
  arm_timer()
end

local function mode_excluded()
  local m = vim.api.nvim_get_mode().mode:sub(1, 1)
  for _, x in ipairs(config.excluded_modes) do
    if m == x then
      return true
    end
  end
  return false
end

local function should_skip(seq)
  if seq == "" then
    return true
  end
  if seq:match("Mouse") then
    return true
  end
  if seq:match("^<Scroll") then
    return true
  end
  if seq:match("^<Cursor") then
    return true
  end
  if seq:match("^<Drag") then
    return true
  end
  if seq:match("^<Focus") then
    return true
  end
  return false
end

local function in_gui()
  return vim.g.neovide or vim.g.fvim_loaded or vim.g.goneovim
end

local function detect_kitty_kb()
  if in_gui() then
    return false
  end
  local term = vim.env.TERM or ""
  local prog = vim.env.TERM_PROGRAM or ""
  if term == "xterm-kitty" or vim.env.KITTY_PID then
    return true
  end
  if prog == "WezTerm" then
    return true
  end
  if term:find("^foot") then
    return true
  end
  if prog == "ghostty" or vim.env.GHOSTTY_RESOURCES_DIR then
    return true
  end
  if prog == "rio" then
    return true
  end
  return false
end

local function enable_kitty_kb()
  local want = config.kitty_keyboard
  if want == false then
    return
  end

  local ok, detected = pcall(detect_kitty_kb)
  if not ok or (want == "auto" and not detected) then
    return
  end

  local sent, err = pcall(vim.fn.chansend, 2, "\27[>1u")
  if not sent then
    vim.notify("[showkeys] kitty keyboard protocol failed: " .. tostring(err), vim.log.levels.DEBUG)
    return
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      pcall(vim.fn.chansend, 2, "\27[<u")
    end,
  })
end

local function on_key(_, typed)
  if not config.enabled then
    return
  end
  if not typed or typed == "" then
    return
  end
  if mode_excluded() then
    return
  end
  local seq = vim.fn.keytrans(typed)
  if should_skip(seq) then
    return
  end

  vim.schedule(function()
    if not config.enabled then
      return
    end
    local mods, main = parse_key(seq)
    push_key(build_label(mods, main))
  end)
end

local function get_fg(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok and hl and hl.fg then
    return hl.fg
  end
  return nil
end

local function setup_highlights()
  vim.api.nvim_set_hl(0, "ShowKeysCap", { link = "Normal", default = true })
  vim.api.nvim_set_hl(0, "ShowKeysCapBorder", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "ShowKeysMod", { link = "Comment", default = true })

  color_count = 0
  local seen = {}
  for _, src in ipairs(config.color_sources) do
    local fg = get_fg(src)
    if fg and not seen[fg] then
      seen[fg] = true
      color_count = color_count + 1
      vim.api.nvim_set_hl(0, "ShowKeysColor" .. color_count, { fg = fg, bold = config.bold })
    end
  end
  if color_count == 0 then
    vim.api.nvim_set_hl(0, "ShowKeysColor1", { bold = config.bold, default = true })
    color_count = 1
  end
end

function M.enable()
  config.enabled = true
end

function M.disable()
  config.enabled = false
  M._wipe()
end

function M.toggle()
  if config.enabled then
    M.disable()
  else
    M.enable()
  end
  vim.notify("ShowKeys: " .. (config.enabled and "on" or "off"))
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  if state.ns then
    return
  end
  math.randomseed(os.time())
  state.ns = vim.api.nvim_create_namespace("user_showkeys")
  setup_highlights()
  vim.on_key(on_key, state.ns)
  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
      setup_highlights()
    end,
    desc = "ShowKeys: re-link highlights after colorscheme change",
  })
  vim.api.nvim_create_user_command("ShowKeysToggle", function()
    M.toggle()
  end, {})

  enable_kitty_kb()
end

return M
