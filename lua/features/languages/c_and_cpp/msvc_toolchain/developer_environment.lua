-- Windows only: Visual Studio's C and C++ toolchain in every Neovim, as a Linux system offers its compiler, libc and
-- kernel headers. vswhere finds the newest instance with the MSVC tools; its VsDevCmd runs once, in the background, and
-- what it changes is kept in stdpath("state")/nvim-config/msvc_developer_environment.json: INCLUDE, LIB, LIBPATH, the
-- VCTools and Windows SDK variables, and the directories it adds to PATH. Each start then sets those (none already set
-- is overwritten) and appends the directories, so a program already on PATH still wins; clangd reads INCLUDE for MSVC's
-- and the SDK's headers, and :terminal and :make get cl, link, nmake and msbuild. A start inside a Developer Prompt
-- changes nothing. Applying costs one file read and one stat; a new Visual Studio version, whose directories the record
-- no longer matches, is captured again in the background.
local M = {}

local uv = vim.uv
local FILE = require("features.maintenance.local_storage").path("state", "msvc_developer_environment.json")
local RECHECK_NONE = 24 * 3600

local capturing = false

local function read()
  local f = io.open(FILE, "rb")

  if not f then
    return nil
  end

  local text = f:read("*a")

  f:close()

  local ok, data = pcall(vim.json.decode, text)

  return ok and type(data) == "table" and data or nil
end

local function write(data)
  vim.fn.mkdir(vim.fs.dirname(FILE), "p")
  pcall(vim.fn.writefile, { vim.json.encode(data) }, FILE)
end

M.read = read

-- Cheap enough for every start: case, separators and a trailing separator only.
local function key(dir)
  return (dir:lower():gsub("\\", "/"):gsub("/+$", ""))
end

local function valid(data)
  local dir = type(data.vars) == "table" and data.vars.VCToolsInstallDir

  return type(dir) == "string" and uv.fs_stat(dir) ~= nil
end

-- libuv's environment calls, not vim.env: no Vimscript round trip for forty variables at every start.
local function apply(data)
  for name, value in pairs(data.vars or {}) do
    if type(value) == "string" and (uv.os_getenv(name) or "") == "" then
      uv.os_setenv(name, value)
    end
  end

  local path = uv.os_getenv("PATH") or ""
  local have = {}

  for dir in vim.gsplit(path, ";", { plain = true, trimempty = true }) do
    have[key(dir)] = true
  end

  for _, dir in ipairs(data.path or {}) do
    if type(dir) == "string" and not have[key(dir)] then
      have[key(dir)] = true
      path = path .. ";" .. dir
    end
  end

  uv.os_setenv("PATH", path)
end

local function vswhere()
  local dir = vim.env["ProgramFiles(x86)"]

  return dir and vim.fs.joinpath(dir, "Microsoft Visual Studio", "Installer", "vswhere.exe")
end

local function arch()
  local machine = (uv.os_uname().machine or ""):lower()

  return (machine:find("arm") or machine:find("aarch")) and "arm64" or "x64"
end

-- Parses `set` output into { NAME = value }, names folded to their spelling in Neovim's own environment.
local function parse_set(text)
  local vars = {}

  for line in vim.gsplit(text, "\r?\n", { trimempty = true }) do
    local name, value = line:match("^([^=]+)=(.*)$")

    if name then
      vars[name] = value
    end
  end

  return vars
end

---@param cb? fun(data: table?, err: string?)
function M.capture(cb)
  cb = cb or function() end
  if vim.fn.has("win32") == 0 or capturing then
    return cb(nil, capturing and "already capturing" or "Windows only")
  end

  local where = vswhere()

  if not where or not uv.fs_stat(where) then
    write({ none = true, when = os.time() })

    return cb(nil, "no Visual Studio Installer (vswhere.exe)")
  end

  capturing = true

  local function done(data, err)
    capturing = false
    cb(data, err)
  end

  vim.system({
    where,
    "-latest",
    "-products",
    "*",
    "-requires",
    "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
    "-format",
    "json",
    "-utf8",
  }, { text = true }, function(res)
    local ok, list = pcall(vim.json.decode, res.stdout or "")
    local vs = ok and type(list) == "table" and list[1]

    if not vs or not vs.installationPath then
      vim.schedule(function()
        write({ none = true, when = os.time() })
        done(nil, "no Visual Studio with the MSVC tools")
      end)

      return
    end

    local devcmd = vim.fs.joinpath(vs.installationPath, "Common7", "Tools", "VsDevCmd.bat")
    local a = arch()

    -- The rest touches Vimscript functions, which a process callback may not call directly.
    vim.schedule(function()
      local script = vim.fn.tempname() .. ".cmd"

      vim.fn.writefile({
        "@chcp 65001 >nul",
        ('@call "%s" -arch=%s -host_arch=%s -no_logo >nul 2>&1'):format(devcmd:gsub("/", "\\"), a, a),
        "@set",
      }, script)

      vim.system({ "cmd", "/d", "/c", script }, { text = true }, function(dev)
        vim.schedule(function()
          os.remove(script)

          local after = parse_set(dev.stdout or "")

          if dev.code ~= 0 or not after.VCToolsInstallDir then
            return done(nil, "VsDevCmd did not set up the MSVC tools")
          end

          local before, seen = vim.fn.environ(), {}

          for name, value in pairs(before) do
            seen[name:lower()] = value
          end

          local vars, path = {}, {}

          for name, value in pairs(after) do
            local lower = name:lower()

            if lower ~= "path" and lower ~= "prompt" and not name:find("^__") and seen[lower] ~= value then
              vars[name] = value
            end
          end

          local have = {}

          for dir in vim.gsplit(seen.path or "", ";", { plain = true, trimempty = true }) do
            have[key(dir)] = true
          end

          for name, value in pairs(after) do
            if name:lower() == "path" then
              for dir in vim.gsplit(value, ";", { plain = true, trimempty = true }) do
                if not have[key(dir)] then
                  have[key(dir)] = true
                  path[#path + 1] = dir
                end
              end
            end
          end

          local data = {
            vs = { name = vs.displayName, version = vs.installationVersion, path = vs.installationPath },
            vars = vars,
            path = path,
            when = os.time(),
          }

          write(data)
          apply(data)
          done(data)
        end)
      end)
    end)
  end)
end

-- At startup (init.lua): apply the record, or capture one in the background after the UI is up.
function M.setup()
  if (uv.os_getenv("VCToolsInstallDir") or "") ~= "" then
    return
  end

  local data = read()

  if data and data.off then
    return
  end

  if data and data.vars and valid(data) then
    return apply(data)
  end

  if data and data.none and os.time() - (data.when or 0) < RECHECK_NONE then
    return
  end

  vim.defer_fn(function()
    M.capture(function(captured)
      if captured then
        vim.notify(
          ("%s %s: cl, link and INCLUDE/LIB are set; clangd and other servers started before this pick them up after a restart."):format(
            captured.vs.name or "Visual Studio",
            captured.vs.version or ""
          ),
          vim.log.levels.INFO,
          { title = "MSVC" }
        )
      end
    end)
  end, 3000)
end

-- <leader>uX: off keeps it off across starts; on captures again now.
function M.set_enabled(on, cb)
  if on then
    os.remove(FILE)

    return M.capture(cb)
  end

  local data = read() or {}

  data.off = true
  write(data)
  cb(data)
end

return M
