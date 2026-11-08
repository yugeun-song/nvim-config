-- Windows only: compile_commands.json for a Visual Studio project, from the settings IntelliSense itself reads,
-- kept up to date the way a kernel tree's database is kept for clangd.
-- MSBuild's design-time target GetClCommandLines gives, per source file, the cl options the build would use
-- (include directories, definitions down to a single file's, the language standard, /EHsc ...). All projects of
-- the nearest .sln, .slnx or .vcxproj are asked in one MSBuild run: a small traversal project calls them with
-- BuildInParallel under -m, so MSBuild spreads them over the cores, in the background. The database goes beside
-- that file, where clangd looks; clangd restarts on it and indexes in the background on every core.
-- A CUDA project's .cu files come from the same run, with the toolkit, GPU, defines and include directories its
-- CUDA build customization resolves (see CUDA_TARGETS below).
-- Opening a C, C++ or CUDA file of such a project rebuilds the database when it is missing or older than its inputs
-- (the solution, each .vcxproj, the .props and .targets they import, Directory.Build.*); when it is current
-- that costs a few stats. A compile_commands.json this did not write (CMake's, say) is left alone, and
-- vim.g.msvc_compiledb_auto = false keeps it to :MsvcCompileDb.
local M = {}

local uv = vim.uv
local STATE = require("features.maintenance.local_storage").path("state", "msvc_compile_databases.json")

local function key(path)
  return vim.fs.normalize(path):lower()
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

-- The .vcxproj files a solution names; a .vcxproj names itself.
local function projects_of(file)
  if file:match("%.vcxproj$") then
    return { vim.fs.normalize(file) }
  end

  local base, found = vim.fs.dirname(file), {}

  for _, line in ipairs(lines_of(file)) do
    local rel = line:match('^Project%(".-"%)%s*=%s*".-",%s*"(.-%.vcxproj)"')
      or line:match('<Project%s+Path="(.-%.vcxproj)"')

    if rel then
      local path = vim.fs.normalize(vim.fs.joinpath(base, (rel:gsub("\\", "/"))))

      if uv.fs_stat(path) then
        found[#found + 1] = path
      end
    end
  end

  return found
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
    local dir = vim.fs.dirname(proj)

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

-- MSBuild of the Visual Studio the MSVC environment recorded, else (with wait) the one vswhere finds.
local function msbuild(wait)
  local arch = (uv.os_uname().machine or ""):lower():find("arm") and "arm64" or "amd64"
  local record = require("features.languages.c_and_cpp.msvc_toolchain.developer_environment").read()
  local vs = record and record.vs and record.vs.path

  if vs then
    local path = vim.fs.joinpath(vs, "MSBuild", "Current", "Bin", arch, "MSBuild.exe")

    if uv.fs_stat(path) then
      return path
    end
  end

  local where = vim.env["ProgramFiles(x86)"]
    and vim.fs.joinpath(vim.env["ProgramFiles(x86)"], "Microsoft Visual Studio", "Installer", "vswhere.exe")

  if wait and where and uv.fs_stat(where) then
    local res = vim
      .system({
        where,
        "-latest",
        "-products",
        "*",
        "-requires",
        "Microsoft.Component.MSBuild",
        "-find",
        ("MSBuild\\**\\Bin\\%s\\MSBuild.exe"):format(arch),
      }, { text = true })
      :wait(10000)

    local path = vim.trim((res.stdout or ""):match("[^\r\n]+") or "")

    if path ~= "" then
      return path
    end
  end
end

-- For :checkhealth: the MSBuild a database would be generated with, asking vswhere if need be.
function M.msbuild_location()
  return msbuild(true)
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
    pcall(vim.cmd, "lsp restart clangd")
  elseif vim.fn.exists(":LspRestart") == 2 then
    pcall(vim.cmd, "LspRestart clangd")
  end
end

local running = {}

local XML = { ["&"] = "&amp;", ['"'] = "&quot;", ["<"] = "&lt;", [">"] = "&gt;" }

local function xml(s)
  return (s:gsub('[&"<>]', XML))
end

-- CUDA: GetClCommandLines covers ClCompile only, and a .cu file is CudaCompile, which NVIDIA's build
-- customization (BuildCustomizations\CUDA x.y.targets) resolves in InitializeCudaProjectProperties: the
-- toolkit the project uses, the -gencode list, and the defines and include directories inherited from the host
-- compiler. This target, imported into a CUDA project through Microsoft.Cpp's ForceImportAfterCppTargets hook,
-- runs that and returns the files with what it resolved; nothing is compiled.
local CUDA_TARGETS = {
  "<Project>",
  '  <Target Name="NvimCudaCompile" Condition="\'@(CudaCompile)\' != \'\'" DependsOnTargets="InitializeCudaProjectProperties" Returns="@(_NvimCuda)">',
  "    <ItemGroup>",
  "      <_NvimCuda Include=\"@(CudaCompile->'%(FullPath)')\" Condition=\"'%(CudaCompile.ExcludedFromBuild)' != 'true'\">",
  "        <NvimToolkit>$(CudaToolkitDir)</NvimToolkit>",
  "        <NvimDirectory>$(MSBuildProjectDirectory)</NvimDirectory>",
  "      </_NvimCuda>",
  "    </ItemGroup>",
  "  </Target>",
  "</Project>",
}

-- A project with CudaCompile items, unless it uses the import hook itself (a global property would replace it).
local function uses_cuda(proj)
  local cuda = false

  for _, line in ipairs(lines_of(proj)) do
    if line:find("ForceImportAfterCppTargets", 1, true) then
      return false
    end

    cuda = cuda or line:find("CudaCompile", 1, true) ~= nil
  end

  return cuda
end

-- The traversal project: every project's GetClCommandLines, in parallel, returned as one target's items; then,
-- for the CUDA projects, NvimCudaCompile. Its own MSBuild call, so a CUDA project whose toolkit is missing
-- loses its .cu entries only.
local function traversal(projects, cuda, configuration, platform, cuda_targets)
  local lines = { "<Project>", "  <ItemGroup>" }

  for _, p in ipairs(projects) do
    lines[#lines + 1] = ('    <P Include="%s" />'):format(xml(p:gsub("/", "\\")))
  end

  for _, p in ipairs(cuda) do
    lines[#lines + 1] = ('    <Cu Include="%s" />'):format(xml(p:gsub("/", "\\")))
  end

  local props = ("Configuration=%s;Platform=%s"):format(configuration, platform)

  vim.list_extend(lines, {
    "  </ItemGroup>",
    '  <Target Name="Collect" Returns="@(Cl)">',
    ('    <MSBuild Projects="@(P)" Targets="GetClCommandLines" Properties="%s" BuildInParallel="true" ContinueOnError="true">'):format(
      props
    ),
    '      <Output TaskParameter="TargetOutputs" ItemName="Cl" />',
    "    </MSBuild>",
  })

  if #cuda > 0 then
    vim.list_extend(lines, {
      ('    <MSBuild Projects="@(Cu)" Targets="NvimCudaCompile" Properties="%s;ForceImportAfterCppTargets=%s" BuildInParallel="true" ContinueOnError="true">'):format(
        props,
        xml(cuda_targets:gsub("/", "\\"))
      ),
      '      <Output TaskParameter="TargetOutputs" ItemName="Cl" />',
      "    </MSBuild>",
    })
  end

  return vim.list_extend(lines, { "  </Target>", "</Project>" })
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

---@param opts? { configuration?: string, platform?: string, dir?: string, auto?: boolean }
function M.generate(opts)
  opts = opts or {}

  local file = project_file(opts.dir or vim.fs.dirname(vim.api.nvim_buf_get_name(0)))

  if not file then
    return not opts.auto
      and vim.notify("No .sln, .slnx or .vcxproj above this file", vim.log.levels.WARN, { title = "MSVC" })
  end

  local root = vim.fs.dirname(file)

  if running[key(root)] then
    return
  end

  local tool = msbuild(not opts.auto)

  if not tool then
    return not opts.auto
      and vim.notify("No MSBuild: Visual Studio or its Build Tools is needed", vim.log.levels.ERROR, { title = "MSVC" })
  end

  local projects = projects_of(file)

  if #projects == 0 then
    return not opts.auto
      and vim.notify(vim.fs.basename(file) .. " names no .vcxproj", vim.log.levels.WARN, { title = "MSVC" })
  end

  -- Taken before MSBuild reads them, so an edit made while it runs shows at the next check.
  local inputs = vim.tbl_map(function(path)
    return { path = path, mtime = mtime(path) }
  end, inputs_of(file, projects))

  local state = read_state()
  local last = state[key(root)] or {}
  local configuration = opts.configuration or last.configuration or "Debug"
  local platform = opts.platform
    or last.platform
    or ((uv.os_uname().machine or ""):lower():find("arm") and "ARM64" or "x64")

  local proj = vim.fn.tempname() .. ".proj"
  local cuda_targets = proj:sub(1, -6) .. ".cuda.targets"
  local cuda = vim.tbl_filter(uses_cuda, projects)
  local started = uv.hrtime()

  running[key(root)] = true
  if #cuda > 0 then
    vim.fn.writefile(CUDA_TARGETS, cuda_targets)
  end

  vim.fn.writefile(traversal(projects, cuda, configuration, platform, cuda_targets), proj)
  if not opts.auto then
    vim.notify(
      ("MSBuild: %d project(s), %s|%s..."):format(#projects, configuration, platform),
      vim.log.levels.INFO,
      { title = "MSVC" }
    )
  end

  vim.system({ tool, proj, "-nologo", "-m", "-nr:false", "-t:Collect", "-getTargetResult:Collect" }, {
    text = true,
  }, function(res)
    vim.schedule(function()
      running[key(root)] = nil
      os.remove(proj)
      os.remove(cuda_targets)

      local ok, data = pcall(vim.json.decode, res.stdout or "")
      local result = ok and type(data) == "table" and data.TargetResults and data.TargetResults.Collect
      local entries = {}

      for _, item in ipairs(result and result.Items or {}) do
        if item.NvimDirectory then
          entries[#entries + 1] = cuda_entry(item)
        else
          for _, src in ipairs(split(item.Files)) do
            entries[#entries + 1] = {
              directory = item.WorkingDirectory,
              file = src,
              command = ('cl.exe %s "%s"'):format(item.Identity, src),
            }
          end
        end
      end

      if #entries == 0 then
        return M.notify_when_ready(
          ("MSBuild gave no compile options for %s (%s|%s)"):format(vim.fs.basename(file), configuration, platform),
          vim.log.levels.WARN
        )
      end

      local db = vim.fs.joinpath(root, "compile_commands.json")

      vim.fn.writefile({ vim.json.encode(entries) }, db)
      state = read_state()
      state[key(root)] = {
        db = vim.fs.normalize(db),
        project = vim.fs.normalize(file),
        configuration = configuration,
        platform = platform,
        inputs = inputs,
        generated = os.time(),
      }

      write_state(state)

      M.notify_when_ready(
        ("compile_commands.json for %s: %d files, %s|%s, %.1f s"):format(
          vim.fs.basename(file),
          #entries,
          configuration,
          platform,
          (uv.hrtime() - started) / 1e9
        )
      )

      restart_clangd()
    end)
  end)
end

local checked = {}

-- On a C or C++ buffer: rebuild the database in the background when it is missing or older than its inputs.
-- Once per project per session, unless one of its inputs is written meanwhile (M.forget).
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

  -- Stale when an input's mtime is not the one recorded: compared for change, not for order, so a file stamped
  -- in the future (a clock off, an archive) does not rebuild at every start.
  local stale = not db_time

  for _, input in ipairs(not stale and mine.inputs or {}) do
    if type(input) ~= "table" or mtime(input.path) ~= input.mtime then
      stale = true

      break
    end
  end

  if stale then
    M.generate({ dir = vim.fs.dirname(name), auto = true })
  end
end

-- The databases this wrote, { db, project, generated } each (lua/features/maintenance/stored_data_paths.lua lists
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
