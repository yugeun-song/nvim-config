-- Windows only: what MSBuild itself says about a Visual Studio solution and its projects. Each question is a small
-- project of our own in Neovim's temporary directory, run with -getTargetResult (MSBuild 17.8 or later); nothing is
-- written beside a solution or a project, and neither is modified.
--   configurations(): a solution's configurations and, under each, every project's own configuration and platform,
--     as MSBuild reads .sln and .slnx, with the configuration it would build by default; or a lone project's.
--   compile_options(): per project, cl's switches for every source (GetClCommandLines), the directories a build
--     puts in INCLUDE (GetProjectDirectories), and what Microsoft's targets call its platform for clang.
-- Two hooks MSBuild offers carry our targets in: DirectorySolutionTargetsPath, into the project MSBuild makes of a
-- solution, and ForceImportAfterCppTargets, into a C++ project. The second goes in as an environment variable, which
-- MSBuild reads as a property of the lowest rank: a project that sets its own keeps it, and ours is skipped there.
local M = {}

local uv = vim.uv

local TARGET = "NvimCollect"
local FACTS = "NvimFacts"

-- A solution of hundreds of projects takes minutes; this only keeps an MSBuild that never ends from staying.
local TIMEOUT_MS = 30 * 60 * 1000

local function tools_architecture()
  return (uv.os_uname().machine or ""):lower():find("arm") and "arm64" or "amd64"
end

-- MSBuild of the Visual Studio the MSVC environment recorded.
local function recorded_msbuild()
  local record = require("features.lang.c.msvc_toolchain.developer_environment").read()
  local vs = record and record.vs and record.vs.path
  local path = vs and vim.fs.joinpath(vs, "MSBuild", "Current", "Bin", tools_architecture(), "MSBuild.exe")

  return path and uv.fs_stat(path) and path or nil
end

-- vswhere's command for the newest MSBuild, at the place the Visual Studio Installer always puts vswhere.
local function vswhere_command()
  local where = vim.env["ProgramFiles(x86)"]
    and vim.fs.joinpath(vim.env["ProgramFiles(x86)"], "Microsoft Visual Studio", "Installer", "vswhere.exe")

  return where
      and uv.fs_stat(where)
      and {
        where,
        "-latest",
        "-products",
        "*",
        "-requires",
        "Microsoft.Component.MSBuild",
        "-find",
        ("MSBuild\\**\\Bin\\%s\\MSBuild.exe"):format(tools_architecture()),
      }
    or nil
end

local function first_line(res)
  local path = vim.trim(((res and res.stdout) or ""):match("[^\r\n]+") or "")

  return path ~= "" and path or nil
end

-- done(path): MSBuild of the Visual Studio the MSVC environment recorded, else the one vswhere finds; nil for none.
---@param done fun(path: string?)
function M.find(done)
  local path, command = recorded_msbuild(), nil

  if path then
    return done(path)
  end

  command = vswhere_command()

  local asked = command
    and pcall(vim.system, command, { text = true, timeout = 10000 }, function(res)
      vim.schedule(function()
        done(first_line(res))
      end)
    end)

  if not asked then
    done(nil)
  end
end

-- The same, waited for (:checkhealth).
---@return string?
function M.find_now()
  local path = recorded_msbuild()

  if path then
    return path
  end

  local command = vswhere_command()

  return command and first_line(vim.system(command, { text = true }):wait(10000)) or nil
end

local XML = { ["&"] = "&amp;", ['"'] = "&quot;", ["<"] = "&lt;", [">"] = "&gt;", ["\r"] = "&#xD;", ["\n"] = "&#xA;" }

local function xml(s)
  return (s:gsub('[&"<>\r\n]', XML))
end

-- Text MSBuild must take as it is, in an item or a property's value: % * ? @ $ ( ) ; ' would expand, glob or
-- split it (MSBuild's special characters, escaped as it escapes them itself).
local function literal(s)
  return xml((s:gsub("[%%%*%?@%$%(%);']", function(c)
    return ("%%%02X"):format(c:byte())
  end)))
end

local function path_literal(path)
  return literal((path:gsub("/", "\\")))
end

M._literal = literal

local ENTITY = { lt = "<", gt = ">", amp = "&", quot = '"', apos = "'" }

local function unescape_xml(s)
  return (
    s:gsub("&(#?)(%w+);", function(numeric, name)
      if numeric == "" then
        return ENTITY[name]
      end

      local code = name:sub(1, 1):lower() == "x" and tonumber(name:sub(2), 16) or tonumber(name)

      return code and vim.fn.nr2char(code, true) or nil
    end)
  )
end

-- The projects of one solution configuration, from the XML MSBuild builds for it:
-- <ProjectConfiguration Project="{guid}" AbsolutePath="..." BuildProjectInSolution="True">Debug|Win32</...>
---@param contents string
---@return { path: string, configuration: string, platform: string }[]
local function projects_in(contents)
  local projects = {}

  for attributes, inner in contents:gmatch("<ProjectConfiguration%s([^>]*)>(.-)</ProjectConfiguration>") do
    local path = attributes:match('AbsolutePath="([^"]*)"')
    local configuration, platform = unescape_xml(inner:match("^[^<]*") or ""):match("^%s*(.-)|(.-)%s*$")

    if path and path ~= "" and configuration then
      projects[#projects + 1] = { path = unescape_xml(path), configuration = configuration, platform = platform }
    end
  end

  return projects
end

M._projects_in = projects_in

-- Returned with every solution's and project's facts: MSBuild's version and the machine's architecture as .NET
-- names it (X64, Arm64), which is how Visual Studio spells its platforms.
local FACT_LINES = {
  "        <NvimConfiguration>$(Configuration)</NvimConfiguration>",
  "        <NvimPlatform>$(Platform)</NvimPlatform>",
  "        <NvimMSBuildVersion>$(MSBuildVersion)</NvimMSBuildVersion>",
  "        <NvimHostArchitecture>$([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)</NvimHostArchitecture>",
}

-- What MSBuild's own solution build passes to each project (the Build target of the project it generates).
M.SOLUTION_PROPERTIES = { "SolutionDir", "SolutionExt", "SolutionFileName", "SolutionName", "SolutionPath" }

-- Imported into the project MSBuild makes of a solution: its configurations (each with its projects' own), and the
-- properties it hands every project it builds.
local function solution_hook()
  local lines = {
    "<Project>",
    '  <Target Name="NvimSolutionConfigurations" Returns="@(_NvimSolution)">',
    "    <ItemGroup>",
    '      <_NvimSolution Include="@(SolutionConfiguration)" />',
    ('      <_NvimSolution Include="%s">'):format(FACTS),
  }

  vim.list_extend(lines, FACT_LINES)
  for _, name in ipairs(M.SOLUTION_PROPERTIES) do
    lines[#lines + 1] = ("        <%s>$(%s)</%s>"):format(name, name, name)
  end

  return vim.list_extend(lines, { "      </_NvimSolution>", "    </ItemGroup>", "  </Target>", "</Project>" })
end

-- CUDA: GetClCommandLines covers ClCompile only, and a .cu file is CudaCompile, which NVIDIA's build
-- customization (BuildCustomizations\CUDA x.y.targets) resolves in InitializeCudaProjectProperties: the toolkit the
-- project uses, the -gencode list, and the defines and include directories inherited from the host compiler. This
-- target runs that and returns the files with what it resolved; nothing is compiled.
local CUDA_TARGET = {
  '  <Target Name="NvimCudaCompile" Condition="\'@(CudaCompile)\' != \'\'" DependsOnTargets="InitializeCudaProjectProperties" Returns="@(_NvimCuda)">',
  "    <ItemGroup>",
  "      <_NvimCuda Include=\"@(CudaCompile->'%(FullPath)')\" Condition=\"'%(CudaCompile.ExcludedFromBuild)' != 'true'\">",
  "        <NvimToolkit>$(CudaToolkitDir)</NvimToolkit>",
  "        <NvimDirectory>$(MSBuildProjectDirectory)</NvimDirectory>",
  "      </_NvimCuda>",
  "    </ItemGroup>",
  "  </Target>",
}

-- Imported into every C++ project of the run. ClangTidyPlatformTargetSwitch is the clang target Microsoft's own
-- targets give clang-tidy for the project's platform (Microsoft.Cpp.ClangTidy.props).
---@param previous string? a ForceImportAfterCppTargets the environment already had: imported too, not replaced
local function project_hook(previous)
  local lines = { "<Project>" }

  if previous and previous ~= "" then
    lines[#lines + 1] = ('  <Import Project="%s" Condition="exists(\'%s\')" />'):format(
      path_literal(previous),
      path_literal(previous)
    )
  end

  vim.list_extend(lines, {
    '  <Target Name="NvimProjectConfigurations" Returns="@(_NvimProject)">',
    "    <ItemGroup>",
    '      <_NvimProject Include="@(ProjectConfiguration)" />',
    ('      <_NvimProject Include="%s">'):format(FACTS),
  })

  vim.list_extend(lines, FACT_LINES)
  vim.list_extend(lines, {
    "      </_NvimProject>",
    "    </ItemGroup>",
    "  </Target>",
    '  <Target Name="NvimProjectFacts" Returns="@(_NvimProjectFacts)">',
    "    <ItemGroup>",
    ('      <_NvimProjectFacts Include="%s">'):format(FACTS),
  })

  vim.list_extend(lines, FACT_LINES)
  vim.list_extend(lines, {
    "        <NvimClangTarget>$(ClangTidyPlatformTargetSwitch)</NvimClangTarget>",
    "        <NvimCompiler>$(ClCompilerPath)</NvimCompiler>",
    "        <NvimPlatformToolset>$(PlatformToolset)</NvimPlatformToolset>",
    "        <NvimDefaultPlatformToolset>$(DefaultPlatformToolset)</NvimDefaultPlatformToolset>",
    -- What Microsoft's own "toolset not found" error (MSB8020) tests; a design-time run only falls back to the
    -- default toolset, as Visual Studio does until the project is retargeted.
    "        <NvimToolsetFound>$(_ToolsetFound)</NvimToolsetFound>",
    "        <NvimWindowsSdk>$(TargetPlatformVersion)</NvimWindowsSdk>",
    "      </_NvimProjectFacts>",
    "    </ItemGroup>",
    "  </Target>",
  })

  vim.list_extend(lines, CUDA_TARGET)
  lines[#lines + 1] = "</Project>"

  return lines
end

---@class MsbuildAnswer
---@field items table[]? the target's items, when MSBuild ran it
---@field code integer MSBuild's exit code; -1 when it could not be started
---@field stderr string MSBuild's errors and warnings
---@field stdout string what it printed besides (the JSON document when all went well)
---@field timed_out boolean?

-- Runs MSBuild on a project of `lines` with the files of `hooks` beside it; done(answer) on the main loop.
---@param msbuild string
---@param lines fun(files: table<string, string>): string[]
---@param hooks table<string, string[]> name -> content
---@param opts { parallel: boolean?, env: table<string, string>? }
---@param done fun(answer: MsbuildAnswer)
local function ask(msbuild, lines, hooks, opts, done)
  local base = vim.fn.tempname()
  local files = { project = base .. ".proj" }

  local function remove_files()
    for _, file in pairs(files) do
      os.remove(file)
    end
  end

  local written, why = pcall(function()
    for name, content in pairs(hooks) do
      files[name] = ("%s.%s.targets"):format(base, name)
      vim.fn.writefile(content, files[name])
    end

    vim.fn.writefile(lines(files), files.project)
  end)

  if not written then
    remove_files()

    return done({ code = -1, stdout = "", stderr = "could not write MSBuild's project: " .. tostring(why) })
  end

  local cmd = { msbuild, files.project, "-nologo", "-nr:false", "-t:" .. TARGET, "-getTargetResult:" .. TARGET }

  if opts.parallel then
    cmd[#cmd + 1] = "-m"
  end

  local env = vim.tbl_extend("force", {}, opts.env or {})

  -- With it set, MSBuild writes UTF-8 whatever the system's code page is; a language the user chose is kept.
  if (uv.os_getenv("DOTNET_CLI_UI_LANGUAGE") or "") == "" then
    env.DOTNET_CLI_UI_LANGUAGE = "en"
  end

  if hooks.project_hook then
    env.ForceImportAfterCppTargets = files.project_hook
  end

  local started, start_error = pcall(vim.system, cmd, { text = true, env = env, timeout = TIMEOUT_MS }, function(res)
    vim.schedule(function()
      remove_files()

      local stdout = res.stdout or ""
      local ok, data = pcall(vim.json.decode, stdout)

      -- A notice before the document (the response file MSBuild read) is not part of it.
      if not ok and stdout:find("\n{", 1, true) then
        ok, data = pcall(vim.json.decode, stdout:sub(stdout:find("\n{", 1, true) + 1))
      end

      local result = ok and type(data) == "table" and type(data.TargetResults) == "table" and data.TargetResults[TARGET]

      done({
        items = type(result) == "table" and type(result.Items) == "table" and result.Items or nil,
        code = res.code,
        stderr = res.stderr or "",
        stdout = result and "" or stdout,
        -- vim.system's own exit code for a process it ended at the timeout.
        timed_out = res.code == 124 and res.signal ~= 0 or nil,
      })
    end)
  end)

  if not started then
    remove_files()
    done({ code = -1, stdout = "", stderr = "could not start MSBuild: " .. tostring(start_error) })
  end
end

---@class MsvcConfigurations
---@field msbuild_version string?
---@field host_architecture string?
---@field default { configuration: string?, platform: string? } what MSBuild builds when nothing is asked for
---@field solution table<string, string>? SolutionDir, SolutionPath ...: nil for a lone project
---@field list { configuration: string, platform: string, contents: string?, projects: { path: string, configuration: string, platform: string }[] }[]

local function configurations_from(items, lone_project)
  local facts, list = {}, {}

  for _, item in ipairs(items) do
    if item.Identity == FACTS then
      facts = item
    elseif (item.Configuration or "") ~= "" and (item.Platform or "") ~= "" then
      list[#list + 1] = {
        configuration = item.Configuration,
        platform = item.Platform,
        contents = item.Content,
        projects = lone_project and {
          { path = lone_project, configuration = item.Configuration, platform = item.Platform },
        } or projects_in(item.Content or ""),
      }
    end
  end

  local solution

  if not lone_project then
    solution = {}
    for _, name in ipairs(M.SOLUTION_PROPERTIES) do
      solution[name] = facts[name]
    end
  end

  return {
    msbuild_version = facts.NvimMSBuildVersion,
    host_architecture = facts.NvimHostArchitecture,
    default = { configuration = facts.NvimConfiguration, platform = facts.NvimPlatform },
    solution = solution,
    list = list,
  }
end

M._configurations_from = configurations_from

-- done(configurations, answer): configurations is nil when MSBuild gave none; answer holds what it said.
---@param msbuild string
---@param file string a .sln, .slnx or .vcxproj
---@param done fun(configurations: MsvcConfigurations?, answer: MsbuildAnswer)
function M.configurations(msbuild, file, done)
  local is_project = file:lower():match("%.vcxproj$") ~= nil

  local function lines(files)
    local call = is_project
        and ('    <MSBuild Projects="%s" Targets="NvimProjectConfigurations" SkipNonexistentTargets="true">'):format(
          path_literal(file)
        )
      or (
        '    <MSBuild Projects="%s" Targets="NvimSolutionConfigurations"'
        .. ' Properties="DirectorySolutionTargetsPath=%s;ImportDirectorySolutionTargets=true">'
      ):format(path_literal(file), path_literal(files.solution_hook))

    return {
      "<Project>",
      ('  <Target Name="%s" Returns="@(NvimOut)">'):format(TARGET),
      call,
      '      <Output TaskParameter="TargetOutputs" ItemName="NvimOut" />',
      "    </MSBuild>",
      "  </Target>",
      "</Project>",
    }
  end

  local hooks = is_project and { project_hook = project_hook(uv.os_getenv("ForceImportAfterCppTargets")) }
    or { solution_hook = solution_hook() }

  ask(msbuild, lines, hooks, {}, function(answer)
    local found = answer.items and configurations_from(answer.items, is_project and file or nil)

    done(found and #found.list > 0 and found or nil, answer)
  end)
end

---@class MsvcCompileRequest
---@field projects { path: string, configuration: string?, platform: string? }[]
---@field solution table<string, string>? the solution's properties (MsvcConfigurations.solution)
---@field contents string? the chosen solution configuration's XML (CurrentSolutionConfigurationContents)

-- done(answer): every item names the project (MSBuildSourceProjectFile) and the target (MSBuildSourceTargetName)
-- it comes from. A project that fails loses its own items only.
---@param msbuild string
---@param request MsvcCompileRequest
---@param done fun(answer: MsbuildAnswer)
function M.compile_options(msbuild, request, done)
  local function lines()
    local out = { "<Project>", "  <ItemGroup>" }

    for _, project in ipairs(request.projects) do
      local own = {}

      if project.configuration then
        own[#own + 1] = "Configuration=" .. literal(project.configuration)
      end

      if project.platform then
        own[#own + 1] = "Platform=" .. literal(project.platform)
      end

      out[#out + 1] = ('    <NvimProject Include="%s"><AdditionalProperties>%s</AdditionalProperties></NvimProject>'):format(
        path_literal(project.path),
        table.concat(own, ";")
      )
    end

    local properties = {}

    if request.solution then
      properties[#properties + 1] = "BuildingSolutionFile=true"
      for _, name in ipairs(M.SOLUTION_PROPERTIES) do
        if request.solution[name] then
          properties[#properties + 1] = name .. "=" .. literal(request.solution[name])
        end
      end

      if request.contents then
        properties[#properties + 1] = "CurrentSolutionConfigurationContents=" .. literal(request.contents)
      end
    end

    -- All projects at once, over the cores. The MSBuild task hands back no project's items when one of them fails
    -- (a project file it cannot load, a target that errors): then each is asked again by itself, which costs
    -- nothing for those already answered, and only the failing one is lost.
    local function call(targets, one_by_one)
      local ask = (
        '    <MSBuild Projects="@(NvimProject)" Targets="%s" Properties="%s" SkipNonexistentTargets="true"'
        .. ' ContinueOnError="true" %s>'
      )

      if not one_by_one then
        return { ask:format(targets, table.concat(properties, ";"), 'BuildInParallel="true"'), "    </MSBuild>" }
      end

      return {
        ask:format(targets, table.concat(properties, ";"), 'BuildInParallel="true"'),
        '      <Output TaskParameter="TargetOutputs" ItemName="NvimAtOnce" />',
        "    </MSBuild>",
        "    <PropertyGroup>",
        "      <NvimAllAnswered>$(MSBuildLastTaskResult)</NvimAllAnswered>",
        "    </PropertyGroup>",
        "    <ItemGroup>",
        "      <NvimOut Include=\"@(NvimAtOnce)\" Condition=\"'$(NvimAllAnswered)' != 'false'\" />",
        '      <NvimAtOnce Remove="@(NvimAtOnce)" />',
        "    </ItemGroup>",
        ask:format(
          targets,
          table.concat(properties, ";"),
          "Condition=\"'$(NvimAllAnswered)' == 'false' and '%(NvimProject.Identity)' != ''\""
        ),
        '      <Output TaskParameter="TargetOutputs" ItemName="NvimOut" />',
        "    </MSBuild>",
      }
    end

    vim.list_extend(out, { "  </ItemGroup>", ('  <Target Name="%s" Returns="@(NvimOut)">'):format(TARGET) })
    vim.list_extend(out, call("GetClCommandLines;GetProjectDirectories;NvimProjectFacts", true))
    -- A call of its own: a CUDA project whose toolkit is missing loses its .cu entries only.
    vim.list_extend(out, call("NvimCudaCompile", true))
    -- The check a build makes of the Windows SDK version a project names (MSB8036 when it is not installed), which
    -- the design-time targets above do not make. Only its errors matter.
    vim.list_extend(out, call("_CheckWindowsSDKInstalled", false))

    return vim.list_extend(out, { "  </Target>", "</Project>" })
  end

  ask(
    msbuild,
    lines,
    { project_hook = project_hook(uv.os_getenv("ForceImportAfterCppTargets")) },
    { parallel = true },
    done
  )
end

return M
