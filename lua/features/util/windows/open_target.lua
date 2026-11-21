-- Windows: vim.ui.open() (gx, Snacks' git browse, an explorer's "open with the system", a language server's
-- window/showDocument) runs `cmd.exe /c start "" <target>`, and cmd.exe reads & in a URL or path as a new command: gx on
-- https://example.com/?a=1&calc runs calc. Here the target goes to Windows PowerShell's
-- [Diagnostics.Process]::Start(), which opens it as Explorer would (ShellExecute), through an environment variable, so
-- no command line holds it; Start-Process would read [ ] in a path as a wildcard. A file that opening runs (a program,
-- a script, a shortcut, an installer) is not opened: open is for documents and links.
local M = {}

local installed = false

-- What opening runs, besides PATHEXT's: shortcuts and what they point to, screen savers, installers, HTML
-- applications, Control Panel items, registry files, Java archives, ClickOnce.
local RUNS = {
  ".lnk",
  ".url",
  ".scr",
  ".msi",
  ".msp",
  ".hta",
  ".cpl",
  ".reg",
  ".pif",
  ".jar",
  ".application",
  ".appref-ms",
  ".settingcontent-ms",
}

local function runs_when_opened(path)
  local ext = (path:match("(%.[^./\\]+)$") or ""):lower()

  if ext == "" then
    return false
  end

  for _, each in ipairs(RUNS) do
    if ext == each then
      return true
    end
  end

  for each in vim.gsplit((vim.env.PATHEXT or ".COM;.EXE;.BAT;.CMD"):lower(), ";", { trimempty = true }) do
    if ext == each then
      return true
    end
  end

  return false
end

-- The local file a target names: a path, or a file: URL's; nil for any other URL.
local function local_file(target)
  local scheme = target:match("^(%a[%w+.-]+):")

  if not scheme then
    return target
  end

  if scheme:lower() == "file" then
    return (
      target:gsub("^[Ff][Ii][Ll][Ee]:/*", ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
      end)
    )
  end

  return nil
end

-- The command and options vim.system() gets for a target, without starting it.
function M.command(target)
  return {
    "powershell.exe",
    "-NoProfile",
    "-NonInteractive",
    "-Command",
    "[void][System.Diagnostics.Process]::Start($env:NVIM_OPEN_TARGET)",
  }, { text = true, detach = true, env = { NVIM_OPEN_TARGET = target } }
end

function M.install()
  if installed then
    return
  end

  installed = true

  local open = vim.ui.open

  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.open = function(path, opt)
    -- A caller naming its own program keeps Neovim's way, as does anything but a string (Neovim reports it).
    if type(path) ~= "string" or (opt and opt.cmd) then
      return open(path, opt)
    end

    -- As Neovim does (a drive path is left as it is), but a $NAME in a name stays.
    if not path:match("%w+:") then
      path = vim.fs.normalize(path, { expand_env = false })
    end

    local file = local_file(path)

    if file and runs_when_opened(file) then
      return nil, ("vim.ui.open: %s runs when opened; it is not opened"):format(file)
    end

    return vim.system(M.command(path)), nil
  end
end

M._runs_when_opened = runs_when_opened
M._local_file = local_file

return M
