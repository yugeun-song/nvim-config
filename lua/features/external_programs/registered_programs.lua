-- Programs registered by path, for tools that are not on PATH (<leader>uX, :ToolPath).
-- stdpath("state")/nvim-config/registered_programs.json maps each name to its program;
-- stdpath("data")/nvim-config/registered_program_shims holds one shim per name and is the only directory this adds to
-- PATH, at its end, so a program's neighbours stay out of reach and anything already on PATH wins. A shim is a symbolic
-- link; on Windows, a copy of winctl that runs the program NAME.shim names. With nothing registered this costs one stat
-- and leaves PATH alone.
local M = {}

local uv = vim.uv
local WIN = vim.fn.has("win32") == 1
local SEP = WIN and ";" or ":"
local STATE = require("features.maintenance.local_storage").path("state", "registered_programs.json")
local SHIMS = require("features.maintenance.local_storage").path("data", "registered_program_shims")

-- Programs this config runs by name, listed first in the picker.
M.KNOWN = {
  { "cscope", "C/C++ and assembler navigation" },
  { "ctags", "the tags file behind <C-]>" },
  { "gdb", "C, C++ and assembly debugger" },
  { "lldb-dap", "LLDB debug adapter" },
  { "yazi", "Open Folder" },
  { "rg", "grep in the picker" },
  { "fd", "files in the picker" },
  { "tree-sitter", "parser builds" },
  { "ruff", "Python lint and format" },
}

local function key(path)
  local p = vim.fs.normalize(path)

  return WIN and p:lower() or p
end

function M.read()
  local ok, lines = pcall(vim.fn.readfile, STATE)

  if not ok then
    return {}
  end

  local dok, tools = pcall(vim.json.decode, table.concat(lines, "\n"))

  return dok and type(tools) == "table" and tools or {}
end

local function write(tools)
  if next(tools) == nil then
    os.remove(STATE)

    return true
  end

  vim.fn.mkdir(vim.fs.dirname(STATE), "p")

  return pcall(vim.fn.writefile, { vim.json.encode(tools) }, STATE)
end

local function shim_of(name)
  return vim.fs.joinpath(SHIMS, WIN and name .. ".exe" or name)
end

local function add_to_path()
  local path = vim.env.PATH or ""
  local want = key(SHIMS)

  for dir in vim.gsplit(path, SEP, { plain = true }) do
    if dir ~= "" and key(dir) == want then
      return
    end
  end

  vim.env.PATH = path .. SEP .. (WIN and SHIMS:gsub("/", "\\") or SHIMS)
end

-- The .shim goes first: a launcher copy without one would run as winctl.
local function make_shim(name, target, launcher)
  vim.fn.mkdir(SHIMS, "p")
  local shim = shim_of(name)

  if not WIN then
    os.remove(shim)

    return uv.fs_symlink(target, shim)
  end

  if not pcall(vim.fn.writefile, { target }, vim.fs.joinpath(SHIMS, name .. ".shim"), "b") then
    return nil, "could not write " .. name .. ".shim"
  end

  launcher = launcher or require("features.windows_platform.winctl").path()
  if not launcher then
    return nil, "the shim launcher (winctl) is not built yet; it is created once winctl is"
  end

  -- A running shim cannot be replaced; it is the same launcher and reads the new .shim on its next start.
  local ok, err = uv.fs_copyfile(launcher, shim)

  if not ok and not uv.fs_stat(shim) then
    return nil, err
  end

  return true
end

-- Windows: a new winctl build becomes every shim's launcher.
function M.refresh_shims(launcher)
  for name, target in pairs(M.read()) do
    make_shim(name, target, launcher)
  end
end

local function check(name, target)
  if not name:match("^[%w][%w._+-]*$") then
    return nil, "a name is letters, digits and . _ + -"
  end

  if vim.fn.isabsolutepath(target) == 0 then
    return nil, target .. " is not an absolute path"
  end

  local st = uv.fs_stat(target)

  if not st or st.type ~= "file" or vim.fn.executable(target) ~= 1 then
    return nil, target .. " is not an executable file"
  end

  -- CreateProcess hands a .cmd or .bat to cmd.exe, which would parse the forwarded arguments again.
  if WIN and not target:lower():match("%.exe$") and not target:lower():match("%.com$") then
    return nil, "on Windows a registered program is an .exe or .com"
  end

  -- A shim, or winctl itself, as the program would start shims in a loop.
  for _, dir in ipairs({ SHIMS, require("features.maintenance.local_storage").path("data", "winctl") }) do
    if key(target):sub(1, #key(dir) + 1) == key(dir) .. "/" then
      return nil, target .. " is a shim or winctl itself, not a program"
    end
  end

  return true
end

---@return boolean? ok, string? err
function M.register(name, target)
  name = WIN and name:gsub("%.[eE][xX][eE]$", "") or name
  target = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(target), ":p"))

  local ok, err = check(name, target)

  if not ok then
    return nil, err
  end

  local tools = M.read()

  tools[name] = target
  if not write(tools) then
    return nil, "could not write " .. STATE
  end

  ok, err = make_shim(name, target)
  add_to_path()

  return ok, err
end

function M.unregister(name)
  local tools = M.read()

  if not tools[name] then
    return nil, name .. " is not registered"
  end

  tools[name] = nil
  write(tools)
  os.remove(shim_of(name))
  if WIN then
    os.remove(vim.fs.joinpath(SHIMS, name .. ".shim"))
  end

  return true
end

-- At startup: PATH gains the shims, and shims a wiped data directory lost are made again.
function M.setup()
  if not uv.fs_stat(STATE) then
    return
  end

  local tools = M.read()

  if next(tools) == nil then
    return
  end

  -- Removed by hand, or by a cleaner: made again, the .shim beside it too.
  for name, target in pairs(tools) do
    if not uv.fs_lstat(shim_of(name)) or (WIN and not uv.fs_stat(vim.fs.joinpath(SHIMS, name .. ".shim"))) then
      make_shim(name, target)
    end
  end

  add_to_path()

  if WIN then
    M.watch_log()
  end
end

local log_watcher

-- Windows: a shim writes its failures to winctl-shim.log beside it (scripts/winctl.c), since it runs for other
-- programs whose stderr Neovim may never see; each new line is shown here. The system reports the directory's
-- changes, so this costs nothing while nothing fails.
function M.watch_log()
  if log_watcher or not WIN then
    return
  end

  local log = vim.fs.joinpath(SHIMS, "winctl-shim.log")
  local st = uv.fs_stat(log)
  local offset = st and st.size or 0
  local handle = uv.new_fs_event()

  if not handle then
    return
  end

  local is_started = handle:start(SHIMS, {}, function(err, filename)
    if err or (filename and filename:lower() ~= "winctl-shim.log") then
      return
    end

    vim.schedule(function()
      local now = uv.fs_stat(log)

      -- Started over past its size limit, or removed: read from its start.
      if not now or now.size < offset then
        offset = 0
      end

      if not now or now.size == offset then
        return
      end

      local fd = uv.fs_open(log, "r", 0)
      local data = fd and uv.fs_read(fd, math.min(now.size - offset, 65536), offset)

      if fd then
        uv.fs_close(fd)
      end

      offset = now.size
      -- The report has its own time; the log's would repeat it.
      for line in (data or ""):gmatch("[^\r\n]+") do
        require("features.windows_platform.winctl").report(
          "winctl shim " .. line:gsub("^%d+%-%d+%-%d+ %d+:%d+:%d+ ", "")
        )
      end
    end)
  end)

  if is_started then
    log_watcher = handle
  else
    handle:close()
  end
end

local function describe(name, tools)
  local found = vim.fn.exepath(name)
  local registered = tools[name]

  if registered then
    local shadow = found ~= "" and not vim.startswith(key(found), key(SHIMS)) and found

    return registered .. (shadow and ("  (PATH has " .. vim.fs.normalize(shadow) .. " first)") or "")
  end

  return found ~= "" and ("PATH: " .. vim.fs.normalize(found)) or "not found"
end

local function report(ok, err, done)
  if ok then
    vim.notify(done, vim.log.levels.INFO, { title = "Tool paths" })
  else
    vim.notify(err or "failed", vim.log.levels.ERROR, { title = "Tool paths" })
  end
end

-- Windows: what the last discovery (lua/features/external_programs/windows_program_discovery.lua) found for name, off
-- this Neovim's PATH.
local function discovered(name)
  local data = WIN and require("features.external_programs.windows_program_discovery").read()
  local hits = data and type(data.found) == "table" and data.found[name] or {}
  local registered = M.read()[name]
  local current = vim.fn.exepath(name)

  -- Only what neither the registration nor PATH already gives; PATH may have caught up since the discovery.
  return vim.tbl_filter(function(hit)
    local k = key(hit.path)

    return not (registered and k == key(registered)) and not (current ~= "" and k == key(current))
  end, hits)
end

local function prompt_path(name, tools)
  vim.ui.input({
    prompt = ("Path to %s (empty unregisters): "):format(name),
    default = tools[name] or "",
    completion = "file",
  }, function(input)
    if input == nil then
      return
    end

    input = vim.trim(input)
    if input == "" then
      if tools[name] then
        report(M.unregister(name), nil, name .. " unregistered")
      end

      return
    end

    local ok, err = M.register(name, input)

    report(ok, err, ("%s -> %s"):format(name, M.read()[name] or input))
  end)
end

function M.prompt(name)
  local tools = M.read()
  local hits = discovered(name)

  if #hits == 0 then
    return prompt_path(name, tools)
  end

  local choices = vim.list_extend({}, hits)

  choices[#choices + 1] = { label = "Enter a path..." }
  if tools[name] then
    choices[#choices + 1] = { label = "Unregister", unregister = true }
  end

  vim.ui.select(choices, {
    prompt = "Register " .. name,
    format_item = function(c)
      return c.path and ("%s  [%s]"):format(c.path, c.via) or c.label
    end,
  }, function(c)
    if not c then
      return
    elseif c.path then
      local ok, err = M.register(name, c.path)

      report(ok, err, ("%s -> %s"):format(name, c.path))
    elseif c.unregister then
      report(M.unregister(name), nil, name .. " unregistered")
    else
      prompt_path(name, tools)
    end
  end)
end

-- Windows: read what the system records (lua/features/external_programs/windows_program_discovery.lua), then show the
-- picker again with it.
function M.discover()
  vim.notify("Reading the registry, installed programs and package managers...", vim.log.levels.INFO, {
    title = "Tool paths",
  })

  require("features.external_programs.windows_program_discovery").run(M.names(), function(result, err)
    if not result then
      return vim.notify(err, vim.log.levels.ERROR, { title = "Tool paths" })
    end

    M.pick()
  end)
end

function M.pick()
  local tools = M.read()
  local items, seen = {}, {}

  local function add(name, why)
    if not seen[name] then
      seen[name] = true
      items[#items + 1] = { name = name, why = why, where = describe(name, tools) }
    end
  end

  for _, known in ipairs(M.KNOWN) do
    add(known[1], known[2])
  end

  for name in pairs(tools) do
    add(name, "registered")
  end

  items[#items + 1] = { why = "Register another program..." }

  if WIN then
    local data = require("features.external_programs.windows_program_discovery").read()
    local missing = data and type(data.missing_path) == "table" and data.missing_path or {}

    for _, item in ipairs(items) do
      local n = item.name and #discovered(item.name) or 0

      if n > 0 then
        item.where = item.where .. ("  (found %d more)"):format(n)
      end
    end

    if #missing > 0 then
      items[#items + 1] = {
        why = ("Add %d PATH directories Windows has and this Neovim lacks (this session)"):format(#missing),
        missing = missing,
      }
    end

    items[#items + 1] = {
      why = "Discover on this system (registry PATH, installed programs, App Paths, Visual Studio, package managers)",
      discover = true,
    }

    local msvc = require("features.languages.c_and_cpp.msvc_toolchain.developer_environment").read() or {}
    local vs = msvc.vs and ("%s %s"):format(msvc.vs.name or "Visual Studio", msvc.vs.version or "") or nil

    items[#items + 1] = {
      why = msvc.off and ("MSVC environment: off%s - turn on"):format(vs and (" (" .. vs .. ")") or "")
        or vs and ("MSVC environment: %s (cl, link, INCLUDE/LIB) - turn off"):format(vs)
        or "MSVC environment: none recorded - look for Visual Studio again",
      msvc = msvc.off or not vs,
    }
  end

  vim.ui.select(items, {
    prompt = "Tool paths",
    format_item = function(item)
      return item.name and ("%-12s %s  [%s]"):format(item.name, item.where, item.why) or item.why
    end,
  }, function(item)
    if not item then
      return
    end

    if item.name then
      return M.prompt(item.name)
    elseif item.discover then
      return M.discover()
    elseif item.msvc ~= nil then
      return require("features.languages.c_and_cpp.msvc_toolchain.developer_environment").set_enabled(
        item.msvc,
        function(data, err)
          local msg = not data and err
            or data.off and "MSVC environment off from the next start"
            or ("%s %s: cl, link and INCLUDE/LIB set; servers started earlier pick them up after a restart"):format(
              data.vs.name,
              data.vs.version
            )

          vim.notify(msg, data and vim.log.levels.INFO or vim.log.levels.ERROR, { title = "MSVC" })
        end
      )
    elseif item.missing then
      require("features.external_programs.windows_program_discovery").add_missing_path(item.missing)

      return vim.notify(table.concat(item.missing, "\n"), vim.log.levels.INFO, { title = "Added to PATH" })
    end

    vim.ui.input({ prompt = "Program name: " }, function(name)
      if name and vim.trim(name) ~= "" then
        M.prompt(vim.trim(name))
      end
    end)
  end)
end

function M.names()
  local names = vim.tbl_map(function(k)
    return k[1]
  end, M.KNOWN)

  for name in pairs(M.read()) do
    if not vim.list_contains(names, name) then
      names[#names + 1] = name
    end
  end

  return names
end

M.STATE, M.SHIMS = STATE, SHIMS

return M
