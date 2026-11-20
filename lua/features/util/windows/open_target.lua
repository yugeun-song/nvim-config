-- Windows: vim.ui.open() (gx, Snacks' git browse, an explorer's "open with the system") runs `cmd.exe /c start ""
-- <target>`, and cmd.exe reads & in a URL or path as a new command: gx on https://example.com/?a=1&calc runs calc.
-- Here the target goes to PowerShell's Start-Process through an environment variable, so no command line holds it.
local M = {}

local installed = false

-- The command and options vim.system() gets for a target, without starting it.
function M.command(target)
  return {
    "powershell.exe",
    "-NoProfile",
    "-NonInteractive",
    "-Command",
    "Start-Process -FilePath $env:NVIM_OPEN_TARGET",
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

    if not path:match("%w+:") then
      path = vim.fs.normalize(path)
    end

    return vim.system(M.command(path)), nil
  end
end

return M
