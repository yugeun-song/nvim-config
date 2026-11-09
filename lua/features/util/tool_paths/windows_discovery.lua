-- Windows only: where this system keeps programs that Neovim's PATH may not show, read from what Windows itself
-- records instead of paths written into this config. One PowerShell run, on request only (<leader>uX), reads
--   the persistent PATH (machine and user, registry): directories added since this Neovim's PATH was inherited;
--   App Paths (registry): programs registered by executable name;
--   the installed programs' InstallLocation (Uninstall registry), with their usual bin layouts beneath it;
--   Visual Studio's instances (vswhere), whose LLVM tools hold clangd and clang-format;
-- and the package managers' own directories follow from their environment variables (winget, Scoop, Chocolatey, Cargo).
-- The result is stdpath("state")/nvim-config/windows_program_discovery.json;
-- lua/features/util/tool_paths/init.lua offers it, nothing applies it.
local M = {}

local uv = vim.uv
local FILE = require("features.util.storage").path("state", "windows_program_discovery.json")

-- Bin directories relative to an install root: MSYS2's environments, Git's cmd, the plain bin.
local LAYOUTS = { "", "bin", "cmd", "usr/bin", "ucrt64/bin", "mingw64/bin", "clang64/bin" }

local SCRIPT = [[
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'
function X($p) { [Environment]::ExpandEnvironmentVariables([string]$p) }
$env_key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$machine = (Get-Item $env_key).GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$user = (Get-Item 'HKCU:\Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$installs = foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') {
  Get-ChildItem $root | ForEach-Object {
    $loc = $_.GetValue('InstallLocation')
    if ($loc) { [ordered]@{ name = [string]$_.GetValue('DisplayName'); location = (X $loc).Trim('"') } }
  }
}
$apppaths = [ordered]@{}
foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths') {
  Get-ChildItem $root | ForEach-Object {
    $v = $_.GetValue('')
    if ($v) { $apppaths[$_.PSChildName] = (X $v).Trim('"') }
  }
}
$vs = @()
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) { $vs = @(& $vswhere -all -products * -property installationPath) }
[ordered]@{
  machine_path = @(($machine -split ';') | Where-Object { $_ } | ForEach-Object { X $_ })
  user_path = @(($user -split ';') | Where-Object { $_ } | ForEach-Object { X $_ })
  installs = @($installs)
  apppaths = $apppaths
  vs = $vs
} | ConvertTo-Json -Depth 4 -Compress
]]

local function key(path)
  return vim.fs.normalize(path):lower()
end

local function is_dir(path)
  local st = path ~= "" and uv.fs_stat(path)

  return st and st.type == "directory"
end

local function program_in(dir, name)
  for _, ext in ipairs({ ".exe", ".com" }) do
    local path = vim.fs.joinpath(dir, name .. ext)
    local st = uv.fs_stat(path)

    if st and st.type == "file" then
      return vim.fs.normalize(path)
    end
  end
end

function M.read()
  local f = io.open(FILE, "rb")

  if not f then
    return nil
  end

  local text = f:read("*a")

  f:close()

  local ok, data = pcall(vim.json.decode, text)

  return ok and type(data) == "table" and data or nil
end

local function as_list(v)
  if type(v) == "string" then
    return { v }
  end

  return type(v) == "table" and v or {}
end

-- Candidate directories with the source each comes from; the first source to name a directory keeps it.
local function directories(raw)
  local dirs, seen = {}, {}

  local function add(dir, via)
    if type(dir) ~= "string" or dir == "" then
      return
    end

    dir = vim.fs.normalize(dir)

    -- A network location (\\server\share) is not looked into: one that does not answer would hold the editor.
    if dir:find("^//") then
      return
    end

    if not seen[key(dir)] and is_dir(dir) then
      seen[key(dir)] = true
      dirs[#dirs + 1] = { dir = dir, via = via }
    end
  end

  for _, dir in ipairs(as_list(raw.machine_path)) do
    add(dir, "machine PATH (registry)")
  end

  for _, dir in ipairs(as_list(raw.user_path)) do
    add(dir, "user PATH (registry)")
  end

  local home = uv.os_homedir() or ""

  add(vim.fs.joinpath(vim.env.LOCALAPPDATA or "", "Microsoft", "WinGet", "Links"), "winget links")
  add(vim.fs.joinpath(vim.env.SCOOP or vim.fs.joinpath(home, "scoop"), "shims"), "Scoop shims")
  add(vim.env.ChocolateyInstall and vim.fs.joinpath(vim.env.ChocolateyInstall, "bin"), "Chocolatey")
  add(vim.fs.joinpath(vim.env.CARGO_HOME or vim.fs.joinpath(home, ".cargo"), "bin"), "Cargo")

  for _, root in ipairs(as_list(raw.vs)) do
    add(vim.fs.joinpath(root, "VC", "Tools", "Llvm", "x64", "bin"), "Visual Studio LLVM (vswhere)")
  end

  for _, install in ipairs(as_list(raw.installs)) do
    if type(install) == "table" and type(install.location) == "string" then
      local label = ((install.name or "") ~= "" and install.name or install.location) .. " (installed programs)"

      for _, sub in ipairs(LAYOUTS) do
        add(sub == "" and install.location or vim.fs.joinpath(install.location, sub), label)
      end
    end
  end

  return dirs
end

-- What the registry's PATH has and this process's lacks: programs installed after this Neovim started.
local function missing_from_process(raw)
  local have = {}

  for dir in vim.gsplit(vim.env.PATH or "", ";", { plain = true, trimempty = true }) do
    have[key(dir)] = true
  end

  local missing = {}

  for _, list in ipairs({ as_list(raw.machine_path), as_list(raw.user_path) }) do
    for _, dir in ipairs(list) do
      if type(dir) == "string" and dir ~= "" and not have[key(dir)] and is_dir(dir) then
        have[key(dir)] = true
        missing[#missing + 1] = vim.fs.normalize(dir)
      end
    end
  end

  return missing
end

---@param names string[]
---@param cb fun(result: table?, err: string?)
function M.run(names, cb)
  if vim.fn.has("win32") == 0 then
    return cb(nil, "tool discovery reads Windows' registry; it is Windows only")
  end

  vim.system(
    { "powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", SCRIPT },
    { text = true, timeout = 30000 },
    vim.schedule_wrap(function(res)
      local ok, raw = pcall(vim.json.decode, res.stdout or "")

      if res.code == 124 then
        return cb(nil, "PowerShell did not answer within 30 seconds")
      end

      if res.code ~= 0 or not ok or type(raw) ~= "table" then
        return cb(nil, "PowerShell gave no readable answer: " .. vim.trim(res.stderr or ""))
      end

      local dirs = directories(raw)
      local found = {}

      for _, name in ipairs(names) do
        local on_path = vim.fn.exepath(name)
        local hits = {}

        local current = on_path ~= "" and key(on_path) or nil

        local app = type(raw.apppaths) == "table" and raw.apppaths[name .. ".exe"]

        if type(app) == "string" and uv.fs_stat(app) and key(app) ~= current then
          hits[#hits + 1] = { path = vim.fs.normalize(app), via = "App Paths (registry)" }
        end

        for _, d in ipairs(dirs) do
          local path = program_in(d.dir, name)

          if path and key(path) ~= current then
            hits[#hits + 1] = { path = path, via = d.via }
          end
        end

        if #hits > 0 then
          found[name] = hits
        end
      end

      local result = { when = os.time(), found = found, missing_path = missing_from_process(raw) }

      vim.fn.mkdir(vim.fs.dirname(FILE), "p")
      pcall(vim.fn.writefile, { vim.json.encode(result) }, FILE)
      cb(result)
    end)
  )
end

-- The registry PATH's directories this Neovim lacks, appended for this session; new processes have them anyway.
function M.add_missing_path(dirs)
  local path = vim.env.PATH or ""

  for _, dir in ipairs(dirs) do
    path = path .. ";" .. dir:gsub("/", "\\")
  end

  vim.env.PATH = path
end

return M
