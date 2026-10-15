local M = {}

local nvim = {
  "███╗   ██╗██╗   ██╗██╗███╗   ███╗",
  "████╗  ██║██║   ██║██║████╗ ████║",
  "██╔██╗ ██║██║   ██║██║██╔████╔██║",
  "██║╚██╗██║╚██╗ ██╔╝██║██║╚██╔╝██║",
  "██║ ╚████║ ╚████╔╝ ██║██║ ╚═╝ ██║",
  "╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝     ╚═╝",
}

-- Small builtin logos of fastfetch (MIT), see THIRD-PARTY-NOTICES.
local logos = {
  arch = [=[
      /\
     /  \
    /    \
   /      \
  /   ,,   \
 /   |  |   \
/_-''    ''-_\]=],
  manjaro = [=[
||||||||| ||||
||||||||| ||||
||||      ||||
|||| |||| ||||
|||| |||| ||||
|||| |||| ||||
|||| |||| ||||]=],
  endeavouros = [=[
          /o.
        /sssso-
      /ossssssso:
    /ssssssssssso+
  /ssssssssssssssso+
//osssssssssssssso+-
 `+++++++++++++++-`]=],
  debian = [=[
  _____
 /  __ \
|  /    |
|  \___-
-_
  --_]=],
  ubuntu = [=[
       ..;,; .,;,.
    .,lool: .ooooo,
   ;oo;:    .coool.
 ....         ''' ,l;
:oooo,            'oo.
looooc            :oo'
 '::'             ,oo:
   ,.,       .... co,
    lo:;.   :oooo; .
     ':ooo; cooooc
        '''  '''']=],
  linuxmint = [=[
 ____________________
|                    \
|_  |   ___________   |
  | |  /  __   __  \  |
  | |  | |  | |  | |  |
  | |  | |  | |  | |  |
  | |  | |  | |  | |  |
  | |  \_/  \_/  | |  |
  | \____________/_/  |
  \___________________/]=],
  pop = [=[
______
\   _ \        __
 \ \ \ \      / /
  \ \_\ \    / /
   \  ___\  /_/
    \ \    _
   __\_\__(_)_
  (___________)`]=],
  fedora = [=[
        ,'''''.
       |   ,.  |
       |  |  '_'
  ,....|  |..
.'  ,_;|   ..'
|  |   |  |
|  ',_,'  |
 '.     ,'
   ''''']=],
  rhel = [=[
      .M.:MMM
     MMMMMMMMMM.
    ,MMMMMMMMMMM
 .MM MMMMMMMMMMM
MMMM   MMMMMMMMM
MMMMMM           MM
 MMMMMMMMM     ,MMMM
   MMMMMMMMMMMMMMMM:
      `MMMMMMMMMMMM]=],
  centos = [=[
 ____^____
 |\  |  /|
 | \ | / |
<---- ---->
 | / | \ |
 |/__|__\|
     v]=],
  opensuse = [=[
  _______
__|   __ \
     / .\ \
     \__/ |
   _______|
   \_______
__________/]=],
  gentoo = [=[
 _-----_
(       \
\    0   \
 \        )
 /      _/
(     _-
\____-]=],
  alpine = [=[
   /\ /\
  // \  \
 //   \  \
///    \  \
//      \  \
         \]=],
  void = [=[
    ____
  'pfPfp.%
//  _._  \\
UU |===| UU
\\  ^~^  //
 `0PpppP'
   `````]=],
  nixos = [=[
  \\  \\ //
 ==\\__\\/ //
   //   \\//
==//     //==
 //\\___//
// /\\  \\==
  // \\  \\]=],
  freebsd = [=[
/\,-'''''-,/\
\_)       (_/
|           |
|           |
 ;         ;
  '-_____-']=],
  macos = [=[
        .:'
    __ :'__
 .'`__`-'__``.
:__________.-'
:_________:
 :_________`-;
  `.__.-.__.']=],
  windows = [=[
lllllll  lllllll
lllllll  lllllll
lllllll  lllllll

lllllll  lllllll
lllllll  lllllll
lllllll  lllllll]=],
  linux = [=[
    ___
   (.. \
   (<> |
  //  \ \
 ( |  | /|
_/\ __)/_)
\/-____\/]=],
}
-- Each logo's main colour: simple-icons (CC0), and Microsoft's Windows logo for windows.
local brand = {
  arch = "#1793d1",
  manjaro = "#35bfa4",
  endeavouros = "#7f7fff",
  debian = "#a81d33",
  ubuntu = "#e95420",
  linuxmint = "#86be43",
  pop = "#48b9c7",
  fedora = "#51a2da",
  rhel = "#ee0000",
  centos = "#262577",
  opensuse = "#73ba25",
  gentoo = "#54487a",
  alpine = "#0d597f",
  void = "#478061",
  nixos = "#5277c3",
  freebsd = "#ab2b28",
  macos = "#000000",
  windows = "#0078d4",
  linux = "#fcc624",
}

local function os_release()
  for _, path in ipairs({ "/etc/os-release", "/usr/lib/os-release" }) do
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok then
      local info = {}
      for _, line in ipairs(lines) do
        local key, value = line:match("^([%w_]+)=(.*)$")
        if key then
          info[key] = value:gsub("^[\"'](.*)[\"']$", "%1")
        end
      end
      return info
    end
  end
  return {}
end

local function detect()
  local sysname = vim.uv.os_uname().sysname
  if sysname == "Darwin" then
    return "macos"
  elseif sysname:find("^Windows") then
    return "windows"
  end
  local info = os_release()
  for id in ((info.ID or "") .. " " .. (info.ID_LIKE or "")):gmatch("%S+") do
    id = id:find("^opensuse") and "opensuse" or id
    if logos[id] then
      return id
    end
  end
  if sysname == "Linux" or sysname == "FreeBSD" then
    return sysname:lower()
  end
end

local function rgb(hex)
  local n = tonumber(hex:sub(2), 16)
  return { math.floor(n / 65536) / 255, math.floor(n / 256) % 256 / 255, n % 256 / 255 }
end

local function to_hex(c)
  local function byte(v)
    return math.floor(math.min(1, math.max(0, v)) * 255 + 0.5)
  end
  return ("#%02x%02x%02x"):format(byte(c[1]), byte(c[2]), byte(c[3]))
end

-- WCAG relative luminance and contrast ratio.
local function luminance(c)
  local sum = 0
  for i, weight in ipairs({ 0.2126, 0.7152, 0.0722 }) do
    local v = c[i]
    sum = sum + weight * (v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4)
  end
  return sum
end

local function contrast(a, b)
  local la, lb = luminance(a), luminance(b)
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

local function to_hsl(c)
  local max, min = math.max(c[1], c[2], c[3]), math.min(c[1], c[2], c[3])
  local l, d = (max + min) / 2, max - min
  if d == 0 then
    return 0, 0, l
  end
  local h
  if max == c[1] then
    h = ((c[2] - c[3]) / d) % 6
  elseif max == c[2] then
    h = (c[3] - c[1]) / d + 2
  else
    h = (c[1] - c[2]) / d + 4
  end
  return h / 6, d / (1 - math.abs(2 * l - 1)), l
end

local function from_hsl(h, s, l)
  local chroma = (1 - math.abs(2 * l - 1)) * s
  local x = chroma * (1 - math.abs((h * 6) % 2 - 1))
  local m = l - chroma / 2
  local rgb_order = {
    { chroma, x, 0 },
    { x, chroma, 0 },
    { 0, chroma, x },
    { 0, x, chroma },
    { x, 0, chroma },
    { chroma, 0, x },
  }
  local c = rgb_order[math.floor(h * 6) % 6 + 1]
  return { c[1] + m, c[2] + m, c[3] + m }
end

-- The logo's own colour, unless it reads below 3:1 on the background; then the nearest shade
-- of the same hue that does, lighter on a dark background, darker on a light one.
local function readable(color, bg)
  local c, b = rgb(color), rgb(bg)
  if contrast(c, b) >= 3 then
    return color
  end
  local h, s, l = to_hsl(c)
  local step = luminance(b) < 0.18 and 0.01 or -0.01
  for i = 1, 100 do
    local shade = from_hsl(h, s, math.min(1, math.max(0, l + step * i)))
    if contrast(shade, b) >= 3 then
      return to_hex(shade)
    end
  end
end

local function width(lines)
  local max = 0
  for _, line in ipairs(lines) do
    max = math.max(max, vim.api.nvim_strwidth(line))
  end
  return max
end

local function pad(lines, height, cols, row)
  local line = lines[row - math.ceil((height - #lines) / 2)] or ""
  return line .. (" "):rep(cols - vim.api.nvim_strwidth(line))
end

local plain = { text = { { table.concat(nvim, "\n"), hl = "header" } }, width = width(nvim) }

local function with_logo()
  local name = detect()
  if not name then
    return nil
  end
  local logo = vim.split(logos[name], "\n", { plain = true })
  local logo_width, nvim_width = width(logo), width(nvim)
  local height = math.max(#logo, #nvim)
  local built = { name = name, text = {}, width = logo_width + 4 + nvim_width }
  for row = 1, height do
    table.insert(built.text, {
      (row > 1 and "\n" or "") .. pad(logo, height, logo_width, row) .. "    ",
      hl = "SnacksDashboardLogo",
    })
    table.insert(built.text, { pad(nvim, height, nvim_width, row), hl = "header" })
  end
  return built
end

local header, terminal_bg, asked

local function background()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  if normal.bg then
    return ("#%06x"):format(normal.bg)
  end
  return terminal_bg or (vim.o.background == "light" and "#ffffff" or "#000000")
end

local function apply()
  local ok, color = pcall(function()
    return header and readable(brand[header.name], background())
  end)
  vim.api.nvim_set_hl(0, "SnacksDashboardLogo", ok and color and { fg = color } or { link = "Special" })
end

-- A transparent Normal shows the terminal's own background, which only the terminal knows (OSC 11).
local function ask_terminal()
  if asked or vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg then
    return
  end
  local tty = false
  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    tty = tty or ui.stdout_tty == true
  end
  if not tty then
    return
  end
  asked = true
  vim.api.nvim_create_autocmd("TermResponse", {
    callback = function(ev)
      local r, g, b = ev.data.sequence:match("^\027%]11;rgba?:(%x+)/(%x+)/(%x+)")
      if not r then
        return
      end
      local function channel(v)
        return tonumber(v, 16) / (16 ^ #v - 1)
      end
      terminal_bg = to_hex({ channel(r), channel(g), channel(b) })
      apply()
      return true
    end,
  })
  vim.api.nvim_ui_send("\027]11;?\007")
end

-- An error, an unknown system or a window too narrow for the logo leaves NVIM alone. The dashboard
-- centres items in a `pane`-wide column and cuts it at the window's right edge when the window is narrower.
function M.section(pane)
  if header == nil then
    local ok, built = pcall(with_logo)
    header = ok and built or false
    if header then
      pcall(ask_terminal)
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          pcall(ask_terminal)
          apply()
        end,
      })
    end
  end
  apply()
  pane = pane or 60
  local room = math.min(pane, 2 * vim.o.columns - pane)
  local shown = header and header.width <= room and header or plain
  return { text = shown.text, align = "center", padding = 2 }
end

return M
