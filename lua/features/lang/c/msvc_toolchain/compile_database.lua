-- Windows only: compile_commands.json for a Visual Studio project, from the settings IntelliSense itself reads,
-- kept up to date the way a kernel tree's database is kept for clangd.
-- MSBuild is asked twice (msbuild_queries.lua): what the nearest .sln or .slnx (else .vcxproj) offers, with each
-- project's own configuration under the solution's; then, for one configuration, every project's cl switches (the
-- design-time target GetClCommandLines), include directories and clang target, evaluated as a solution build
-- evaluates it ($(SolutionDir) and the rest). Each source becomes one entry (clangd_command.lua); a CUDA project's
-- .cu files come from the same run, with what its CUDA build customization resolves. The database goes beside
-- that file, where clangd looks; clangd restarts on it and indexes in the background on every core.
-- Opening a C, C++ or CUDA file of such a project rebuilds the database when it is missing or behind: an input
-- changed (the solution, each .vcxproj, the .props and .targets they import, Directory.Build.*), the toolchain its
-- entries name changed (a Visual Studio or Windows SDK update), or this file writes it differently now. When it is
-- current that costs a few stats. A compile_commands.json this did not write (CMake's, say) is left alone, and
-- vim.g.msvc_compiledb_auto = false keeps it to :MsvcCompileDb.
-- A run that cannot give a whole database says why, with MSBuild's own errors, and keeps MSBuild's output in
-- stdpath("state")/nvim-config/msvc_compile_database.log.
local M = {}

local uv = vim.uv
local storage = require("features.util.storage")
local STATE = storage.path("state", "msvc_compile_databases.json")
local LOG = storage.path("state", "msvc_compile_database.log")

-- How this file writes a database; a recorded one of another number is rebuilt.
local FORMAT = 2
local LOG_MAX_BYTES = 256 * 1024
local SHOWN_ERRORS = 6

local function key(path)
  return vim.fs.normalize(path):lower()
end

-- One spelling per file: MSBuild answers with long names where a short one (PROGRA~1) was asked.
local function canonical(path)
  return key(uv.fs_realpath(path) or path)
end

-- A path for the user to read and paste.
local function as_windows_writes(path)
  return (path:gsub("/", "\\"))
end

local function mtime(path)
  local st = uv.fs_stat(path)

  return st and st.mtime.sec or nil
end

local function read_state()
  local f = io.open(STATE, "rb")

  if not f then
    return {}
  end

  local text = f:read("*a")

  f:close()

  local ok, data = pcall(vim.json.decode, text)

  return ok and type(data) == "table" and data or {}
end

local function write_state(data)
  vim.fn.mkdir(vim.fs.dirname(STATE), "p")
  pcall(vim.fn.writefile, { vim.json.encode(data) }, STATE)
end

local project_for_dir = {}

-- The nearest solution, else the nearest project, above dir, in one walk up that reads each directory once;
-- remembered per directory for the session.
local function project_file(dir)
  local hit = project_for_dir[dir]

  if hit ~= nil then
    return hit or nil
  end

  local project

  for parent in vim.fs.parents(vim.fs.joinpath(dir, "x")) do
    for name, kind in vim.fs.dir(parent) do
      if kind == "file" then
        if name:match("%.slnx?$") then
          hit = vim.fs.joinpath(parent, name)

          break
        elseif not project and name:match("%.vcxproj$") then
          project = vim.fs.joinpath(parent, name)
        end
      end
    end

    if hit then
      break
    end
  end

  hit = hit or project or false
  project_for_dir[dir] = hit

  return hit or nil
end

M.project_file = project_file

local function lines_of(file)
  local ok, lines = pcall(vim.fn.readfile, file)

  return ok and lines or {}
end

-- What a project's compile options come from: itself, the property sheets it imports by a plain path, and the
-- Directory.Build files MSBuild picks up above it.
local function inputs_of(file, projects)
  local inputs, seen = {}, {}

  local function add(path)
    if path and not seen[key(path)] and uv.fs_stat(path) then
      seen[key(path)] = true
      inputs[#inputs + 1] = vim.fs.normalize(path)
    end
  end

  add(file)
  for _, proj in ipairs(projects) do
    local dir = vim.fs.dirname(vim.fs.normalize(proj))

    add(proj)
    for _, line in ipairs(lines_of(proj)) do
      local rel = line:match('<Import%s+Project="([^"$]+)"')

      if rel then
        add(vim.fs.joinpath(dir, (rel:gsub("\\", "/"))))
      end
    end

    for _, name in ipairs({ "Directory.Build.props", "Directory.Build.targets" }) do
      add(vim.fs.find(name, { upward = true, path = dir, limit = 1 })[1])
    end
  end

  return inputs
end

-- What the entries point into: the system include directories that exist, and the directory two levels above
-- each (...\MSVC over <version>\include, ...\Include over <version>\ucrt), whose time changes when a toolset or SDK
-- version comes or goes.
local function toolchain_of(directories)
  local listings, seen = {}, {}

  for _, dir in ipairs(directories) do
    local listing = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(dir)))
    local time = mtime(listing)

    if time and not seen[key(listing)] then
      seen[key(listing)] = true
      listings[#listings + 1] = { path = listing, mtime = time }
    end
  end

  return { directories = directories, listings = listings }
end

local function toolchain_changed(toolchain)
  if type(toolchain) ~= "table" then
    return true
  end

  for _, dir in ipairs(toolchain.directories or {}) do
    if type(dir) ~= "string" or not uv.fs_stat(dir) then
      return true
    end
  end

  for _, listing in ipairs(toolchain.listings or {}) do
    if type(listing) ~= "table" or mtime(listing.path) ~= listing.mtime then
      return true
    end
  end

  return false
end

-- For :checkhealth: the MSBuild a database would be generated with, asking vswhere if need be.
function M.msbuild_location()
  return require("features.lang.c.msvc_toolchain.msbuild_queries").find_now()
end

-- A message raised while Neovim starts (a file argument's FileType) would land before the notifier loads, in
-- the message area, and stop at "Press ENTER"; it waits for VeryLazy instead.
function M.notify_when_ready(msg, level)
  local function show()
    vim.notify(msg, level or vim.log.levels.INFO, { title = "MSVC" })
  end

  -- lazy.nvim sets it as it fires VeryLazy.
  if vim.g.did_very_lazy then
    return vim.schedule(show)
  end

  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    once = true,
    callback = function()
      vim.schedule(show)
    end,
  })
end

-- clangd keeps the absent database of files already open; Neovim 0.12's :lsp restarts it, nvim-lspconfig's
-- :LspRestart where that is what there is.
local function restart_clangd()
  if #vim.lsp.get_clients({ name = "clangd" }) == 0 then
    return
  end

  if vim.fn.exists(":lsp") == 2 then
    pcall(vim.api.nvim_command, "lsp restart clangd")
  elseif vim.fn.exists(":LspRestart") == 2 then
    pcall(vim.api.nvim_command, "LspRestart clangd")
  end
end

local function split(list)
  return vim.split(list or "", ";", { plain = true, trimempty = true })
end

-- A .cu file for clangd: clang's CUDA mode with the project's toolkit (clang looks for one by itself on Windows
-- only where CUDA 7 and 8 installed), the first real GPU of its -gencode list, and its defines and include
-- directories. A toolkit newer than the clang knows is fine for parsing; -Wno-unknown-cuda-version says so.
local function cuda_entry(item)
  local args = { "clang++", "-x", "cuda", "-Wno-unknown-cuda-version" }
  local toolkit = item.NvimToolkit ~= "" and item.NvimToolkit or vim.env.CUDA_PATH
  local codegen = item.CodeGeneration or ""
  local virtual = codegen:match("compute_(%d+%a?)")
  local arch = codegen:match("sm_%d+%a?") or (virtual and "sm_" .. virtual)
  local std = (item.AdditionalOptions or ""):match("%-%-?std[= ]+(c%+%+%d+)")

  if toolkit and toolkit ~= "" then
    args[#args + 1] = "--cuda-path=" .. vim.fs.normalize(toolkit)
  end

  if arch then
    args[#args + 1] = "--cuda-gpu-arch=" .. arch
  end

  if std then
    args[#args + 1] = "-std=" .. std
  end

  for _, def in ipairs(split(item.Defines)) do
    args[#args + 1] = "-D" .. def
  end

  for _, dir in ipairs(split(item.Include)) do
    args[#args + 1] = "-I" .. dir
  end

  args[#args + 1] = item.Identity

  return { directory = item.NvimDirectory, file = item.Identity, arguments = args }
end

local function same(a, b)
  return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

-- The configuration to read the projects in. Asked for: that one, or nil when the solution has no such. Else the
-- last one used, the machine's own platform, and what MSBuild itself would build, in that order, as far as offered.
---@param found MsvcConfigurations
---@param asked { configuration: string?, platform: string? }
---@param last { configuration: string?, platform: string? }
local function choose(found, asked, last)
  local function offered(configuration, platform)
    for _, c in ipairs(found.list) do
      if same(c.configuration, configuration) and (not platform or same(c.platform, platform)) then
        return c
      end
    end
  end

  -- The first candidate that is offered: a configuration, or a platform of `under`. "" stands for none.
  local function first_offered(candidates, under)
    for _, candidate in ipairs(candidates) do
      local hit

      if under then
        hit = offered(under, candidate)
      else
        hit = offered(candidate)
      end

      if candidate ~= "" and hit then
        return candidate
      end
    end
  end

  local configuration = asked.configuration
    or first_offered({ last.configuration or "", found.default.configuration or "" })
    or found.list[1].configuration

  local platform = asked.platform
    or first_offered(
      { last.platform or "", found.host_architecture or "", found.default.platform or "" },
      configuration
    )
    or (offered(configuration) or {}).platform

  return platform and offered(configuration, platform) or nil
end

M._choose = choose

local function names(found)
  return vim.tbl_map(function(c)
    return c.configuration .. "|" .. c.platform
  end, found.list)
end

-- MSBuild's error lines, each once, without the project path it appends: "file(1,2): error MSB8020: ... [project]".
local function errors_in(text)
  local lines, seen = {}, {}

  for line in vim.gsplit(text or "", "\r?\n") do
    if line:find(": error ", 1, true) or line:find("^%s*MSBUILD : error") then
      line = vim.trim(line)
      if not seen[line] then
        seen[line] = true
        lines[#lines + 1] = line
      end
    end
  end

  return lines
end

-- What MSBuild printed, kept for the user to read: the summary the notification gave, then its output.
local function write_log(summary, answers)
  local lines = { os.date("%Y-%m-%d %H:%M:%S"), "" }

  vim.list_extend(lines, summary)
  for _, answer in ipairs(answers) do
    vim.list_extend(lines, { "", ("-- MSBuild, exit code %s --"):format(tostring(answer.code)) })
    vim.list_extend(lines, vim.split(answer.stderr or "", "\r?\n", { trimempty = true }))
    vim.list_extend(lines, vim.split(answer.stdout or "", "\r?\n", { trimempty = true }))
  end

  local text = table.concat(lines, "\n")

  if #text > LOG_MAX_BYTES then
    text = text:sub(1, LOG_MAX_BYTES) .. "\n... (cut)"
  end

  local f = io.open(LOG, "wb")

  if f then
    f:write(text, "\n")
    f:close()
  end
end

-- The entries as text, an entry a line with its keys in one order: vim.json.encode orders a table's keys by their
-- hashes, which differ from one Neovim to the next, and the same database must read the same to be known as such.
local function as_json(entries)
  local lines = {}

  for i, entry in ipairs(entries) do
    lines[i] = ('{"directory":%s,"file":%s,"arguments":%s}'):format(
      vim.json.encode(entry.directory),
      vim.json.encode(entry.file),
      vim.json.encode(entry.arguments)
    )
  end

  return "[\n" .. table.concat(lines, ",\n") .. "\n]\n"
end

M._as_json = as_json

-- compile_commands.json, whole or not at all: written beside itself and moved over, and left alone when it says
-- the same already. A link or a directory of that name is not written through, and the temporary file is made
-- anew, never opened where something waits under its name.
---@return boolean? changed true when written, false when it said the same already, nil when it could not be
---@return string? why
local function write_database(db, entries)
  local st = uv.fs_lstat(db)

  if st and st.type ~= "file" then
    return nil, ("%s is a %s, not a file"):format(db, st.type)
  end

  local text = as_json(entries)
  local old = st and io.open(db, "rb")

  if old then
    local same_text = old:read("*a") == text

    old:close()
    if same_text then
      return false
    end
  end

  local partial = ("%s.%d.tmp"):format(db, uv.os_getpid())

  os.remove(partial)

  local fd, open_error = uv.fs_open(partial, "wx", 420)

  if not fd then
    return nil, tostring(open_error)
  end

  local written, write_error = uv.fs_write(fd, text)

  uv.fs_close(fd)

  local moved, move_error

  if written == #text then
    moved, move_error = uv.fs_rename(partial, db)
  end

  if not moved then
    os.remove(partial)

    return nil, tostring(write_error or move_error or "the disk took only part of it")
  end

  return true
end

-- The entries of every project MSBuild answered for, and what to tell about the others.
---@param projects { path: string, configuration: string?, platform: string? }[]
---@param items table[] compile_options()'s items
local function entries_of(projects, items)
  local clangd_command = require("features.lang.c.msvc_toolchain.clangd_command")
  local answers, by_other_spelling = {}, nil

  for _, item in ipairs(items) do
    local owner = item.MSBuildSourceProjectFile

    if type(owner) == "string" then
      local k = key(owner)

      answers[k] = answers[k] or { commands = {}, cuda = {} }

      local target = item.MSBuildSourceTargetName

      if target == "GetClCommandLines" then
        table.insert(answers[k].commands, item)
      elseif target == "NvimCudaCompile" then
        table.insert(answers[k].cuda, item)
      elseif target == "GetProjectDirectories" then
        answers[k].directories = item
      elseif target == "NvimProjectFacts" then
        answers[k].facts = item
      end
    end
  end

  -- MSBuild names a project as it was asked for, apart from a long name for a short one: the file system is asked
  -- for the one spelling only when the plain one finds nothing.
  local function answer_for(path)
    if answers[key(path)] then
      return answers[key(path)]
    end

    if not by_other_spelling then
      by_other_spelling = {}
      for k, answer in pairs(answers) do
        by_other_spelling[canonical(k)] = answer
      end
    end

    return by_other_spelling[canonical(path)]
  end

  -- The same toolset and SDK directories come back for every project: each is looked at once.
  local known = {}

  local function exists(path)
    if known[path] == nil then
      known[path] = uv.fs_stat(path) ~= nil
    end

    return known[path]
  end

  local entries, notes, silent, system, seen = {}, {}, {}, {}, {}

  for _, project in ipairs(projects) do
    local answer = answer_for(project.path)
    local name = vim.fs.basename(vim.fs.normalize(project.path))

    if not answer or not answer.directories then
      silent[#silent + 1] = name
    else
      local facts = answer.facts or {}
      local listed = clangd_command.directories(answer.directories.IncludePath, answer.directories.ExternalIncludePath)
      local includes = vim.tbl_filter(exists, listed)

      for _, dir in ipairs(includes) do
        if not seen[dir] then
          seen[dir] = true
          system[#system + 1] = dir
        end
      end

      local compiler = facts.NvimCompiler
      local facts_for_clangd = {
        driver = compiler and compiler ~= "" and exists(compiler) and compiler or nil,
        target = facts.NvimClangTarget,
        system_includes = includes,
      }

      for _, item in ipairs(answer.commands) do
        vim.list_extend(entries, clangd_command.entries(item, facts_for_clangd))
      end

      for _, item in ipairs(answer.cuda) do
        entries[#entries + 1] = cuda_entry(item)
      end

      if not answer.facts then
        notes[#notes + 1] = ("%s sets ForceImportAfterCppTargets itself: its clang target and .cu files were not read"):format(
          name
        )
      elseif
        facts.NvimToolsetFound ~= "true"
        and (facts.NvimPlatformToolset or "") ~= ""
        -- Not for the default toolset itself: were that property ever renamed, every project would be named here.
        and not same(facts.NvimPlatformToolset, facts.NvimDefaultPlatformToolset)
      then
        notes[#notes + 1] = (
          "%s: platform toolset %s is not installed; MSBuild read the project with its default%s, as Visual Studio "
          .. "does until the project is retargeted (a build stops with MSB8020)"
        ):format(
          name,
          facts.NvimPlatformToolset,
          (facts.NvimDefaultPlatformToolset or "") ~= "" and (" (" .. facts.NvimDefaultPlatformToolset .. ")") or ""
        )
      end

      if #listed > 0 and #includes == 0 then
        notes[#notes + 1] = ("%s: none of its %d include directories exist (the first: %s)"):format(
          name,
          #listed,
          listed[1]
        )
      end
    end
  end

  return entries, { notes = notes, silent = silent, system_includes = system }
end

-- The oldest Clang the toolset's C++ library accepts, as the library's own check says it (yvals_core.h: STL1000,
-- "Unexpected compiler version, expected Clang 22 or newer.").
local function clang_wanted_in(text)
  return tonumber(text:match("STL1000[^\n]-expected Clang (%d+)"))
end

M._clang_wanted_in = clang_wanted_in

local function clang_wanted_by(directories)
  for _, dir in ipairs(directories) do
    local f = io.open(vim.fs.joinpath(dir, "yvals_core.h"), "rb")

    if f then
      local text = f:read("*a")

      f:close()

      return clang_wanted_in(text)
    end
  end
end

-- done(major, version, path) of the clangd Neovim starts (lua/plugins/lang/c.lua: the first on PATH). Asked once
-- per program file as it is: an update replaces the file, and is asked again.
local clangd_known = {}

local function clangd_version(done)
  local exe = vim.fn.exepath("clangd")
  local st = exe ~= "" and uv.fs_stat(exe)
  local as_is = st and ("%s|%d|%d"):format(exe, st.mtime.sec, st.size)

  if as_is and clangd_known.as_is == as_is then
    return done(clangd_known.major, clangd_known.version, exe)
  end

  local started = as_is
    and pcall(vim.system, { exe, "--version" }, { text = true, timeout = 10000 }, function(res)
      vim.schedule(function()
        local version = (res.stdout or ""):match("clangd version ([%d%.]+)")
        local major = version and tonumber(version:match("^%d+"))

        if major then
          clangd_known = { as_is = as_is, major = major, version = version }
        end

        done(major, version, exe)
      end)
    end)

  if not started then
    done(nil)
  end
end

-- What to tell about a clangd older than the C++ library accepts. Mason's is updated by Mason, which on Windows
-- removes the old one first and cannot while it runs.
local function clangd_too_old(version, exe, wanted)
  local masons = vim.startswith(key(exe), key(vim.fs.joinpath(vim.fn.stdpath("data"), "mason")) .. "/")

  return {
    ("clangd %s is older than this toolset's C++ library accepts (Clang %d or newer): a source that includes it shows error STL1000."):format(
      version,
      wanted
    ),
    masons
        and "Update it while clangd is not running (before a C-family file is opened, or after :lsp stop): :MasonInstall clangd"
      or ("A newer clangd is needed first on PATH; Neovim starts " .. as_windows_writes(exe)),
  }
end

M._clangd_too_old = clangd_too_old

local running = {}

function M._busy()
  return next(running) ~= nil
end

-- Runs body(await) as a coroutine: await(ask) hands ask a callback and comes back with what it is called with.
-- failed(message) hears of an error in body itself.
local function in_steps(body, failed)
  local co

  local function await(ask)
    local answered, waiting, values, count = false, false, {}, 0

    ask(function(...)
      values, count, answered = { ... }, select("#", ...), true
      if waiting then
        coroutine.resume(co)
      end
    end)

    if not answered then
      waiting = true
      coroutine.yield()
    end

    return unpack(values, 1, count)
  end

  co = coroutine.create(function()
    local ok, err = xpcall(body, debug.traceback, await)

    if not ok then
      failed(tostring(err))
    end
  end)

  coroutine.resume(co)
end

---@param opts? { configuration?: string, platform?: string, dir?: string, auto?: boolean }
function M.generate(opts)
  opts = opts or {}

  local file = project_file(opts.dir or vim.fs.dirname(vim.api.nvim_buf_get_name(0)))

  if not file then
    return not opts.auto
      and vim.notify("No .sln, .slnx or .vcxproj above this file", vim.log.levels.WARN, { title = "MSVC" })
  end

  local root = vim.fs.dirname(file)
  local shown = vim.fs.basename(file)

  if running[key(root)] then
    return
  end

  local queries = require("features.lang.c.msvc_toolchain.msbuild_queries")
  local started = uv.hrtime()
  local answers = {}
  local msbuild

  running[key(root)] = true

  -- Ends the run: what happened and MSBuild's own words; where its whole output is, when MSBuild is what failed
  -- (its errors, or about_msbuild). quietly: to the log only.
  local function finish(level, summary, version, about_msbuild, quietly)
    running[key(root)] = nil

    local errors = {}

    for _, answer in ipairs(answers) do
      vim.list_extend(errors, errors_in(answer.stderr))
      vim.list_extend(errors, errors_in(answer.stdout))
    end

    local lines = vim.list_extend({}, summary)

    for n = 1, math.min(#errors, SHOWN_ERRORS) do
      lines[#lines + 1] = errors[n]
    end

    if #errors > SHOWN_ERRORS then
      lines[#lines + 1] = ("... and %d more"):format(#errors - SHOWN_ERRORS)
    end

    if msbuild and (about_msbuild or #errors > 0) then
      lines[#lines + 1] = ("MSBuild %s (%s); its output: %s"):format(
        version or "of an unknown version",
        as_windows_writes(msbuild),
        as_windows_writes(LOG)
      )
    end

    write_log(lines, answers)
    if not quietly then
      M.notify_when_ready(table.concat(lines, "\n"), level)
    end
  end

  in_steps(function(await)
    msbuild = await(queries.find)
    if not msbuild then
      return finish(vim.log.levels.ERROR, {
        ("No compile_commands.json for %s: no MSBuild."):format(shown),
        "Visual Studio or its Build Tools, with the C++ tools, is needed; vswhere is what finds it.",
      })
    end

    local found, first = await(function(done)
      queries.configurations(msbuild, file, done)
    end)

    answers[#answers + 1] = first
    if not found then
      local unknown_switch = (first.stdout .. first.stderr):find("MSB1001", 1, true)

      return finish(vim.log.levels.ERROR, {
        ("No compile_commands.json for %s: MSBuild could not read it%s."):format(
          shown,
          first.timed_out and " in time" or (" (exit code %d)"):format(first.code)
        ),
        unknown_switch
            and "This MSBuild does not know -getTargetResult, which 17.8 brought: a newer Visual Studio is needed."
          or nil,
      }, nil, true)
    end

    local last = read_state()[key(root)] or {}
    local chosen = choose(found, { configuration = opts.configuration, platform = opts.platform }, last)

    if not chosen then
      return finish(vim.log.levels.ERROR, {
        ("No compile_commands.json for %s: it has no configuration %s|%s."):format(
          shown,
          opts.configuration or "*",
          opts.platform or "*"
        ),
        "It has: " .. table.concat(names(found), ", "),
      }, found.msbuild_version)
    end

    local projects = vim.tbl_filter(function(project)
      return project.path:lower():match("%.vcxproj$") ~= nil
    end, chosen.projects)

    if #projects == 0 then
      return finish(vim.log.levels.WARN, {
        ("No compile_commands.json for %s: %s|%s builds no .vcxproj."):format(
          shown,
          chosen.configuration,
          chosen.platform
        ),
      }, found.msbuild_version)
    end

    -- Taken before MSBuild reads them, so an edit made while it runs shows at the next check.
    local inputs = vim.tbl_map(
      function(path)
        return { path = path, mtime = mtime(path) }
      end,
      inputs_of(
        file,
        vim.tbl_map(function(project)
          return project.path
        end, projects)
      )
    )

    if not opts.auto then
      vim.notify(
        ("MSBuild: %d project(s), %s|%s..."):format(#projects, chosen.configuration, chosen.platform),
        vim.log.levels.INFO,
        { title = "MSVC" }
      )
    end

    local second = await(function(done)
      queries.compile_options(
        msbuild,
        { projects = projects, solution = found.solution, contents = chosen.contents },
        done
      )
    end)

    answers[#answers + 1] = second

    local entries, told = entries_of(projects, second.items or {})

    if #entries == 0 then
      return finish(vim.log.levels.ERROR, {
        ("No compile_commands.json for %s (%s|%s): MSBuild gave no compile options%s."):format(
          shown,
          chosen.configuration,
          chosen.platform,
          second.timed_out and " in time" or (" (exit code %d)"):format(second.code)
        ),
      }, found.msbuild_version, true)
    end

    local db = vim.fs.joinpath(root, "compile_commands.json")
    -- A project directory may be read-only (a mounted share, a checkout of someone else's).
    local changed, write_error = write_database(db, entries)

    if changed == nil then
      return finish(vim.log.levels.ERROR, {
        ("Could not write %s: %s"):format(db, tostring(write_error)),
      }, found.msbuild_version)
    end

    local state = read_state()

    state[key(root)] = {
      db = vim.fs.normalize(db),
      project = vim.fs.normalize(file),
      configuration = chosen.configuration,
      platform = chosen.platform,
      configurations = names(found),
      inputs = inputs,
      toolchain = toolchain_of(told.system_includes),
      format = FORMAT,
      generated = os.time(),
    }

    write_state(state)

    local summary = {
      ("compile_commands.json for %s%s: %d files of %d project(s), %s|%s, %.1f s"):format(
        shown,
        changed and "" or " says the same as before",
        #entries,
        #projects - #told.silent,
        chosen.configuration,
        chosen.platform,
        (uv.hrtime() - started) / 1e9
      ),
    }

    if #told.silent > 0 then
      summary[#summary + 1] = ("MSBuild gave nothing for %d project(s): %s"):format(
        #told.silent,
        table.concat(told.silent, ", ")
      )
    end

    vim.list_extend(summary, told.notes)

    -- What MSBuild's own part left to tell; a clangd that is too old is clangd's.
    local whole = #told.silent == 0 and #told.notes == 0 and #errors_in(second.stderr) == 0

    -- Microsoft's C++ library refuses a Clang older than the one it was written against: say so before every
    -- source that includes it does.
    local wanted = clang_wanted_by(told.system_includes)
    local major, version, exe

    if wanted then
      major, version, exe = await(clangd_version)
    end

    local too_old = major ~= nil and major < wanted

    if too_old then
      vim.list_extend(summary, clangd_too_old(version, exe, wanted))
    end

    local level = whole and not too_old and vim.log.levels.INFO or vim.log.levels.WARN

    -- The same database again has nothing for clangd to read anew, and nothing to tell when Neovim asked by itself.
    finish(level, summary, found.msbuild_version, not whole, opts.auto and not changed and level == vim.log.levels.INFO)
    if changed then
      restart_clangd()
    end
  end, function(message)
    running[key(root)] = nil
    M.notify_when_ready("compile database, an error of its own: " .. message, vim.log.levels.ERROR)
  end)
end

local checked = {}

-- On a C or C++ buffer: rebuild the database in the background when it is missing or behind. Once per project per
-- session, unless one of its inputs is written meanwhile (M.forget).
function M.ensure(buf)
  if vim.g.msvc_compiledb_auto == false then
    return
  end

  local name = vim.api.nvim_buf_get_name(buf)

  if name == "" then
    return
  end

  local file = project_file(vim.fs.dirname(name))

  if not file then
    return
  end

  local root = vim.fs.dirname(file)
  local k = key(root)

  if checked[k] then
    return
  end

  checked[k] = true

  local db = vim.fs.joinpath(root, "compile_commands.json")
  local db_time = mtime(db)
  local mine = read_state()[k]

  -- Someone else's database: not this one's to replace.
  if db_time and not mine then
    return
  end

  -- MSBuild runs what a project defines (property functions, tasks, targets, the Directory.Build files above it):
  -- a project is evaluated unasked only after :MsvcCompileDb has made its database once, which is the consent.
  if not mine then
    M.notify_when_ready(
      (
        "No compile_commands.json for %s; :MsvcCompileDb makes one (MSBuild evaluates the project and runs what it "
        .. "defines)"
      ):format(vim.fn.fnamemodify(file, ":~:.")),
      vim.log.levels.INFO
    )

    return
  end

  -- Behind when an input's mtime is not the one recorded: compared for change, not for order, so a file stamped
  -- in the future (a clock off, an archive) does not rebuild at every start.
  local behind = not db_time or mine.format ~= FORMAT or toolchain_changed(mine.toolchain)

  for _, input in ipairs(not behind and mine.inputs or {}) do
    if type(input) ~= "table" or mtime(input.path) ~= input.mtime then
      behind = true

      break
    end
  end

  if behind then
    M.generate({ dir = vim.fs.dirname(name), auto = true })
  end
end

-- :MsvcCompileDb's completion: the configurations, then the platforms, the last run found the project to have.
---@param line string the command line so far
---@return string[]
function M.complete(line)
  local file = project_file(vim.fs.dirname(vim.api.nvim_buf_get_name(0)))
  local record = file and read_state()[key(vim.fs.dirname(file))]
  local words = vim.split(vim.trim(line), "%s+")
  local position = #words - (line:match("%s$") and 0 or 1)
  local candidates, seen = {}, {}

  for _, name in ipairs(record and type(record.configurations) == "table" and record.configurations or {}) do
    local configuration, platform = tostring(name):match("^(.-)|(.*)$")
    local candidate = position <= 1 and configuration or (same(configuration, words[2]) and platform or nil)

    if candidate and not seen[candidate] then
      seen[candidate] = true
      candidates[#candidates + 1] = candidate
    end
  end

  return candidates
end

-- The databases this wrote, { db, project, generated } each (lua/features/util/managed_paths.lua lists
-- them).
function M.databases()
  local list = {}

  for _, rec in pairs(read_state()) do
    if type(rec) == "table" and rec.db then
      list[#list + 1] = { db = rec.db, project = rec.project, generated = rec.generated }
    end
  end

  return list
end

-- A written project file, property sheet or solution: the next C or C++ buffer checks again.
function M.forget()
  checked = {}
  project_for_dir = {}
end

return M
