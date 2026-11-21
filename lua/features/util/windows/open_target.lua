-- Windows: vim.ui.open() (gx, Snacks' git browse, an explorer's "open with the system", a language server's
-- window/showDocument) runs `cmd.exe /c start "" <target>`, and cmd.exe reads & in a URL or path as a new command: gx on
-- https://example.com/?a=1&calc runs calc. Here the target goes to Windows PowerShell's
-- [Diagnostics.Process]::Start(), which opens it as Explorer would (ShellExecute), through an environment variable, so
-- no command line holds it; Start-Process would read [ ] in a path as a wildcard. A file that opening runs (a program,
-- a script, a shortcut, an installer) is not opened: open is for documents and links. A local target is judged as the
-- file it is (its real path: Windows drops a trailing dot or space, and reads evil.exe::$DATA as evil.exe), and one
-- that is not there is not opened (Windows would look a bare name up as a program). Of the URLs only http, https and
-- mailto are opened: a scheme's handler can run anything, as ms-msdt: did.
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

local URLS = { http = true, https = true, mailto = true }

-- The local file a target names: a path, or a file: URL's without its query and fragment; nil for any other URL.
local function local_file(target)
  local scheme = target:match("^(%a[%w+.-]+):")

  if not scheme then
    return target
  end

  if scheme:lower() == "file" then
    return (
      target:gsub("^[Ff][Ii][Ll][Ee]:/*", ""):gsub("[?#].*$", ""):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
      end)
    )
  end

  return nil
end

-- What to open for target, or nil and why it is not opened.
local function resolve(target)
  local file = local_file(target)

  if not file then
    local scheme = target:match("^(%a[%w+.-]+):"):lower()

    if URLS[scheme] then
      return target
    end

    return nil, ("vim.ui.open: %s: only http, https and mailto links are opened"):format(target)
  end

  local real = vim.uv.fs_realpath(file)

  if not real then
    return nil, ("vim.ui.open: %s is not there; it is not opened"):format(file)
  end

  if runs_when_opened(real) then
    return nil, ("vim.ui.open: %s runs when opened; it is not opened"):format(file)
  end

  return real
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

-- The opener, as vim.system()'s object. gx waits a second for it (wait(1000)) and kills it then, and Windows PowerShell
-- can take longer to start: nothing would open. wait() here never kills; an opener still running when it returns ends
-- alone, and a failure nobody waited for is said when it ends. command is for tests.
function M.start(target, command)
  local cmd, opts = (command or M.command)(target)
  local result, seen = nil, false

  local proc = vim.system(cmd, opts, function(done)
    result = done

    if done.code ~= 0 then
      vim.schedule(function()
        if not seen then
          vim.notify(
            ("vim.ui.open: %s was not opened (exit %d) %s"):format(target, done.code, vim.trim(done.stderr or "")),
            vim.log.levels.ERROR
          )
        end
      end)
    end
  end)

  return setmetatable({
    wait = function(_, timeout)
      vim.wait(timeout or 60000, function()
        return result ~= nil
      end)

      seen = result ~= nil

      return result or { code = 0, signal = 0, stdout = "", stderr = "" }
    end,
  }, { __index = proc })
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

    local target, why = resolve(path)

    if not target then
      return nil, why
    end

    return M.start(target), nil
  end
end

M._runs_when_opened = runs_when_opened
M._local_file = local_file
M._resolve = resolve

return M
