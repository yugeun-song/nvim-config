-- lua/features/lang/c/msvc_toolchain/: compile_commands.json for Visual Studio projects.
--   nvim -l tests/msvc_compile_database/check.lua
-- Everywhere: how a cl command line becomes a clangd entry and how a configuration is chosen, with nothing run.
-- On Windows with Visual Studio: solutions it writes itself (.sln and .slnx, under a directory named with a
-- space, Korean and "&") go through MSBuild for real, and clangd, when there is one, must read a source of them
-- without an error. Elsewhere those steps print SKIP. Everything it writes is in a throwaway root.
local script = vim.fs.normalize(vim.fn.fnamemodify(arg[0], ":p"))
local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(script)))

-- The modules keep their state in stdpath("state"): run again with every stdpath in a throwaway root, so the
-- user's own are never touched. clangd is looked for first, where the user's Neovim finds it.
if not os.getenv("MSVC_COMPILE_DATABASE_TEST_ROOT") then
  local root = vim.fn.tempname() .. "-msvc-compile-database"
  local clangd = vim.fn.exepath("clangd")

  for _, name in ipairs(clangd == "" and { "clangd.cmd", "clangd" } or {}) do
    local mason = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", name)

    if clangd == "" and vim.uv.fs_stat(mason) then
      clangd = mason
    end
  end

  local env = { MSVC_COMPILE_DATABASE_TEST_ROOT = root, MSVC_COMPILE_DATABASE_TEST_CLANGD = clangd }

  for _, kind in ipairs({ "CONFIG", "DATA", "STATE", "CACHE" }) do
    env["XDG_" .. kind .. "_HOME"] = vim.fs.joinpath(root, kind:lower())
  end

  local res = vim.system({ vim.v.progpath, "-l", script }, { env = env, text = true }):wait()

  io.stdout:write(res.stdout or "")
  io.stderr:write(res.stderr or "")
  vim.fs.rm(root, { recursive = true, force = true })
  vim.cmd.cquit(res.code)
end

package.path = vim.fs.joinpath(repo, "lua", "?.lua")
  .. ";"
  .. vim.fs.joinpath(repo, "lua", "?", "init.lua")
  .. ";"
  .. package.path

local uv = vim.uv
local failures = 0

local function check(ok, what)
  failures = failures + (ok and 0 or 1)
  print((ok and "PASS " or "FAIL ") .. what:gsub("\n", "\n     "))
end

local function same(got, want, what)
  local ok = vim.deep_equal(got, want)

  check(ok, ok and what or ("%s\n     want %s\n     got  %s"):format(what, vim.inspect(want), vim.inspect(got)))
end

local clangd_command = require("features.lang.c.msvc_toolchain.clangd_command")
local split = clangd_command.split

-- Each of these is split the same way by clangd 21 and 22 (their --check --log=verbose prints the command).
same(split([[/c /I"C:\a b\Include" /W3]]), { "/c", [[/IC:\a b\Include]], "/W3" }, "a quoted directory")
same(split([[/Fo"x64\Debug\\" /Gd]]), { [[/Fox64\Debug\]], "/Gd" }, "a trailing backslash before the closing quote")
same(split([[/D "NAME=\"quoted value\"" /TP]]), { "/D", [[NAME="quoted value"]], "/TP" }, "escaped quotes")
same(split([[/D VALUE=a\b /I C:\dir\ /X]]), { "/D", [[VALUE=a\b]], "/I", [[C:\dir\]], "/X" }, "bare backslashes")
same(split([[/I"C:\dir\" /Dnext"]]), { [[/IC:\dir" /Dnext]] }, "one backslash escapes the quote")
same(split([[/Da\\\"b /Dc]]), { [[/Da\"b]], "/Dc" }, "three backslashes and a quote")
same(split([[/Da\\\\"b c" /Dd]]), { [[/Da\\b c]], "/Dd" }, "four backslashes and a quote")
same(split([[/D"a""b" /Dc]]), { [[/Da"b]], "/Dc" }, "a doubled quote inside quotes")
same(split([["" x]]), { "", "x" }, "an empty argument")
same(split("  a\t\tb \r\n"), { "a", "b" }, "runs of whitespace")
same(split([[/D "X=1;Y" /D"Z= "]]), { "/D", "X=1;Y", "/DZ= " }, "a semicolon and a trailing space")
same(split(""), {}, "nothing")

same(
  clangd_command.directories([[C:\a;;C:\b\;c:\A;]], nil, [[C:\c; C:\b]]),
  { [[C:\a]], [[C:\b\]], [[C:\c]] },
  "directories: empty items, repeats in another case or with a trailing separator, a missing list"
)

local entries = clangd_command.entries({
  Identity = [[/c /I"C:\sln\Include" /W3 /D _DEBUG /external:W3 /std:c++20 /Fo"x64\Debug\\" /TP]],
  Files = [[C:\sln\app\main.cpp;C:\sln\app\other.cpp]],
  WorkingDirectory = [[C:\sln\app]],
}, {
  driver = [[C:\VS\bin\cl.exe]],
  target = "--target=amd64-pc-windows-msvc",
  system_includes = { [[C:\VS\include]], [[C:\Kits\ucrt]] },
})

check(#entries == 2 and entries[2].file == [[C:\sln\app\other.cpp]], "one entry per file of the item")
same(entries[1], {
  directory = [[C:\sln\app]],
  file = [[C:\sln\app\main.cpp]],
  arguments = {
    [[C:\VS\bin\cl.exe]],
    "--target=amd64-pc-windows-msvc",
    "/imsvc",
    [[C:\VS\include]],
    "/imsvc",
    [[C:\Kits\ucrt]],
    "/c",
    [[/IC:\sln\Include]],
    "/W3",
    "/D",
    "_DEBUG",
    "/std:c++20",
    [[/Fox64\Debug\]],
    "/TP",
    [[C:\sln\app\main.cpp]],
  },
}, "the entry: compiler, target, the project's system directories, cl's switches without /external:W3, the file")

local function arguments(identity, project)
  return clangd_command.entries(
    { Identity = identity, Files = [[C:\p\a.c]], WorkingDirectory = [[C:\p]] },
    project or {}
  )[1].arguments
end

same(arguments("/c /external:W0 -external:W4"), { "cl.exe", "/c", "/external:W0", [[C:\p\a.c]] }, "/external:W0 stays")
same(
  arguments([[/c /D "X=/external:W3"]]),
  { "cl.exe", "/c", "/D", "X=/external:W3", [[C:\p\a.c]] },
  "a definition that merely spells the switch stays"
)

same(
  arguments("/c /X", { system_includes = { [[C:\VS\include]] } }),
  { "cl.exe", "/c", "/X", [[C:\p\a.c]] },
  "/X: the project ignores the standard include path, so none is added"
)

same(
  arguments("/c --target=arm64-pc-windows-msvc", { target = "--target=amd64-pc-windows-msvc" }),
  { "cl.exe", "/c", "--target=arm64-pc-windows-msvc", [[C:\p\a.c]] },
  "a target the project's own switches name is not doubled"
)

same(arguments("/c", { target = "" }), { "cl.exe", "/c", [[C:\p\a.c]] }, "no target known: none invented")
same(
  clangd_command.entries({ Identity = "/c", Files = "", WorkingDirectory = [[C:\p]] }, {}),
  {},
  "an item without files gives no entry"
)

local queries = require("features.lang.c.msvc_toolchain.msbuild_queries")

same(
  queries._projects_in(
    '<SolutionConfiguration>\r\n  <ProjectConfiguration Project="{1}" AbsolutePath="C:\\a &amp; b\\x.vcxproj" '
      .. 'BuildProjectInSolution="True">Debug|Win32</ProjectConfiguration>\r\n  <ProjectConfiguration Project="{2}" '
      .. 'AbsolutePath="C:\\it&apos;s\\y.vcxproj" BuildProjectInSolution="False">Release Static|x64'
      .. '<ProjectDependency Project="{1}" /></ProjectConfiguration>\r\n</SolutionConfiguration>'
  ),
  {
    { path = [[C:\a & b\x.vcxproj]], configuration = "Debug", platform = "Win32" },
    { path = [[C:\it's\y.vcxproj]], configuration = "Release Static", platform = "x64" },
  },
  "a solution configuration's projects: XML escapes undone, a dependency element ignored"
)

same(
  queries._literal([[C:\50% (x86);a$b@c'd*e?f & "g" <h>]]),
  [[C:\50%25 %28x86%29%3Ba%24b%40c%27d%2Ae%3Ff &amp; &quot;g&quot; &lt;h&gt;]],
  "text MSBuild must take literally: its special characters, then XML's"
)

local database = require("features.lang.c.msvc_toolchain.compile_database")
local choose = database._choose

local function offer(list, default, host)
  local found = { list = {}, default = { configuration = default[1], platform = default[2] }, host_architecture = host }

  for _, name in ipairs(list) do
    local configuration, platform = name:match("^(.-)|(.*)$")

    found.list[#found.list + 1] = { configuration = configuration, platform = platform }
  end

  return found
end

local function chosen(found, asked, last)
  local c = choose(found, asked or {}, last or {})

  return c and (c.configuration .. "|" .. c.platform)
end

local both = offer({ "Debug|Win32", "Debug|x64", "Release|Win32", "Release|x64" }, { "Debug", "Win32" }, "X64")

same(chosen(both), "Debug|x64", "nothing asked: the machine's own platform when the solution has it")
same(chosen(both, { platform = "win32" }), "Debug|Win32", "a platform asked for, in the solution's spelling")
same(chosen(both, { configuration = "Release" }), "Release|x64", "a configuration asked for")
same(chosen(both, {}, { configuration = "Release", platform = "Win32" }), "Release|Win32", "the last one used")
same(chosen(both, { configuration = "Debug", platform = "ARM64" }), nil, "one the solution has not: none")
same(chosen(both, { configuration = "Profile" }), nil, "a configuration it has not: none")
same(
  chosen(both, {}, { configuration = "Gone", platform = "ARM" }),
  "Debug|x64",
  "a last one that is gone is passed over"
)

same(
  chosen(offer({ "Release|ARM64", "Checked|ARM64" }, { "Debug", "Win32" }, "X64")),
  "Release|ARM64",
  "neither the default nor the machine's: the first it has"
)

same(
  chosen(offer({ "Debug|Mixed Platforms", "Debug|x86" }, { "Debug", "Mixed Platforms" }, "X64")),
  "Debug|Mixed Platforms",
  "the machine's platform is not offered: what MSBuild itself would build"
)

same(
  database._clang_wanted_in(
    '#if __clang_major__ < 22\n_EMIT_STL_ERROR(STL1000, "Unexpected compiler version, expected Clang 22 or newer.");\n'
  ),
  22,
  "the Clang a toolset's C++ library asks for, from its own error text"
)

same(database._clang_wanted_in("nothing of the kind"), nil, "no such text: nothing is claimed")

same(
  database._as_json({
    { arguments = { "cl.exe", [[/IC:\a b]], "a.c" }, file = [[C:\p\a.c]], directory = [[C:\p]] },
    { directory = [[C:\p]], file = [[C:\p\한.c]], arguments = { "cl.exe", 'X="y"' } },
  }),
  table.concat({
    "[",
    [[{"directory":"C:\\p","file":"C:\\p\\a.c","arguments":["cl.exe","/IC:\\a b","a.c"]},]],
    [[{"directory":"C:\\p","file":"C:\\p\\한.c","arguments":["cl.exe","X=\"y\""]}]],
    "]",
    "",
  }, "\n"),
  "the database's text: an entry a line, its keys in one order whatever Neovim writes it"
)

local masons = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", "clangd.cmd")
local advice = database._clangd_too_old("21.1.8", masons, 22)

check(
  #advice == 2 and advice[1]:find("clangd 21.1.8", 1, true) and advice[1]:find("Clang 22 or newer", 1, true),
  "a clangd too old: its version and the one wanted"
)

check(
  advice[2]:find(":MasonInstall clangd", 1, true) and advice[2]:find("not running", 1, true),
  "Mason's clangd: updated by Mason, while clangd does not run"
)

advice = database._clangd_too_old("21.1.8", "C:/Program Files/LLVM/bin/clangd.exe", 22)
check(
  advice[2]:find([[C:\Program Files\LLVM\bin\clangd.exe]], 1, true) and not advice[2]:find("Mason", 1, true),
  "another clangd: named as Windows writes it, and Mason is not"
)

-- From here on MSBuild runs for real.
local msbuild = vim.fn.has("win32") == 1 and queries.find_now() or nil

if not msbuild then
  print("SKIP the runs through MSBuild: " .. (vim.fn.has("win32") == 1 and "no MSBuild found" or "Windows only"))
  print(("== %d failed"):format(failures))
  vim.cmd.cquit(failures == 0 and 0 or 1)
end

vim.g.did_very_lazy = true

local told = {}

-- Catches what would be shown, instead of showing it.
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(message, level)
  told[#told + 1] = { message = tostring(message), level = level }
end

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end

local APP, LIB = "{11111111-1111-4111-8111-111111111111}", "{22222222-2222-4222-8222-222222222222}"

---@param opts { guid: string, kind: string, sources: string[], toolset: string?, sdk: string? }
local function vcxproj(opts)
  local lines = {
    '<?xml version="1.0" encoding="utf-8"?>',
    '<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">',
    '  <ItemGroup Label="ProjectConfigurations">',
  }

  for _, platform in ipairs({ "Win32", "x64" }) do
    for _, configuration in ipairs({ "Debug", "Release" }) do
      lines[#lines + 1] = ('    <ProjectConfiguration Include="%s|%s"><Configuration>%s</Configuration><Platform>%s</Platform></ProjectConfiguration>'):format(
        configuration,
        platform,
        configuration,
        platform
      )
    end
  end

  vim.list_extend(lines, {
    "  </ItemGroup>",
    '  <PropertyGroup Label="Globals">',
    ("    <ProjectGuid>%s</ProjectGuid>"):format(opts.guid),
    opts.sdk and ("    <WindowsTargetPlatformVersion>%s</WindowsTargetPlatformVersion>"):format(opts.sdk) or "",
    "  </PropertyGroup>",
    '  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.Default.props" />',
    '  <PropertyGroup Label="Configuration">',
    ("    <ConfigurationType>%s</ConfigurationType>"):format(opts.kind),
    -- Whatever toolset the Visual Studio that runs this has.
    ("    <PlatformToolset>%s</PlatformToolset>"):format(opts.toolset or "$(DefaultPlatformToolset)"),
    "    <CharacterSet>Unicode</CharacterSet>",
    "  </PropertyGroup>",
    '  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.props" />',
    "  <ItemDefinitionGroup>",
    "    <ClCompile>",
    "      <LanguageStandard>stdcpp20</LanguageStandard>",
    '      <PreprocessorDefinitions>FIXTURE_TEXT="a b";%(PreprocessorDefinitions)</PreprocessorDefinitions>',
    "    </ClCompile>",
    "  </ItemDefinitionGroup>",
    "  <ItemGroup>",
  })

  for _, source in ipairs(opts.sources) do
    lines[#lines + 1] = ('    <ClCompile Include="%s" />'):format(source)
  end

  return vim.list_extend(lines, {
    "  </ItemGroup>",
    '  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.targets" />',
    "</Project>",
  })
end

-- A solution of an application and a library whose headers are in $(SolutionDir)Include; the solution's x86 is
-- the projects' Win32.
---@param dir string
---@param format "sln"|"slnx"
---@param opts { toolset: string?, sdk: string? }?
local function solution(dir, format, opts)
  opts = opts or {}
  write(vim.fs.joinpath(dir, "Directory.Build.props"), {
    "<Project>",
    "  <ItemDefinitionGroup>",
    "    <ClCompile>",
    "      <AdditionalIncludeDirectories>$(SolutionDir)Include;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>",
    "    </ClCompile>",
    "  </ItemDefinitionGroup>",
    "</Project>",
  })

  write(vim.fs.joinpath(dir, "Include", "shared.h"), { "#pragma once", "inline int shared_value() { return 42; }" })
  -- No C++ library header: Microsoft's refuses a clangd older than its toolset, which is not what is tested here.
  write(vim.fs.joinpath(dir, "app", "main.cpp"), {
    "#include <Windows.h>",
    "#include <stdio.h>",
    "",
    '#include "shared.h"',
    "",
    'static_assert(sizeof(FIXTURE_TEXT) == 4, "a quoted definition with a space survives");',
    "",
    "int main()",
    "{",
    '    printf("%d %lu\\n", shared_value(), GetCurrentProcessId());',
    "    return 0;",
    "}",
  })

  write(vim.fs.joinpath(dir, "app", "util.c"), { "#include <stdio.h>", "", "int util(void) { return 0; }" })
  write(vim.fs.joinpath(dir, "lib", "lib.cpp"), { '#include "shared.h"', "", "int lib() { return shared_value(); }" })
  write(
    vim.fs.joinpath(dir, "app", "app.vcxproj"),
    vcxproj({
      guid = APP,
      kind = "Application",
      sources = { "main.cpp", "util.c" },
      toolset = opts.toolset,
      sdk = opts.sdk,
    })
  )

  write(
    vim.fs.joinpath(dir, "lib", "lib.vcxproj"),
    vcxproj({ guid = LIB, kind = "StaticLibrary", sources = { "lib.cpp" } })
  )

  if format == "slnx" then
    write(vim.fs.joinpath(dir, "Fixture.slnx"), {
      "<Solution>",
      "  <Configurations>",
      '    <Platform Name="x64" />',
      '    <Platform Name="x86" />',
      "  </Configurations>",
      ('  <Project Path="app/app.vcxproj" Id="%s" />'):format(APP:sub(2, -2)),
      ('  <Project Path="lib/lib.vcxproj" Id="%s" />'):format(LIB:sub(2, -2)),
      "</Solution>",
    })

    return
  end

  local lines = {
    "",
    "Microsoft Visual Studio Solution File, Format Version 12.00",
    ('Project("{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}") = "app", "app\\app.vcxproj", "%s"'):format(APP),
    "EndProject",
    ('Project("{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}") = "lib", "lib\\lib.vcxproj", "%s"'):format(LIB),
    "EndProject",
    "Global",
    "\tGlobalSection(SolutionConfigurationPlatforms) = preSolution",
  }

  for _, configuration in ipairs({ "Debug", "Release" }) do
    for _, platform in ipairs({ "x64", "x86" }) do
      lines[#lines + 1] = ("\t\t%s|%s = %s|%s"):format(configuration, platform, configuration, platform)
    end
  end

  vim.list_extend(lines, { "\tEndGlobalSection", "\tGlobalSection(ProjectConfigurationPlatforms) = postSolution" })
  for _, guid in ipairs({ APP, LIB }) do
    for _, configuration in ipairs({ "Debug", "Release" }) do
      for _, platform in ipairs({ "x64", "x86" }) do
        local own = configuration .. "|" .. (platform == "x86" and "Win32" or platform)

        for _, what in ipairs({ "ActiveCfg", "Build.0" }) do
          lines[#lines + 1] = ("\t\t%s.%s|%s.%s = %s"):format(guid, configuration, platform, what, own)
        end
      end
    end
  end

  write(vim.fs.joinpath(dir, "Fixture.sln"), vim.list_extend(lines, { "\tEndGlobalSection", "EndGlobal" }))
end

-- generate() to its last word: the notification that names the database or says why there is none.
local function generate(opts)
  local before = #told

  database.forget()
  database.generate(opts)
  vim.wait(600000, function()
    local last = told[#told]

    return #told > before and last ~= nil and not last.message:find("^MSBuild: %d+ project")
  end, 20)

  return told[#told] or { message = "", level = -1 }
end

local function read_database(dir)
  local f = io.open(vim.fs.joinpath(dir, "compile_commands.json"), "rb")

  if not f then
    return nil
  end

  local text = f:read("*a")

  f:close()

  return vim.json.decode(text)
end

local function entry_of(list, name)
  for _, entry in ipairs(list or {}) do
    if entry.file:lower():sub(-#name) == name:lower() then
      return entry
    end
  end
end

local function has(list, value)
  for _, item in ipairs(list or {}) do
    if item:lower() == value:lower() then
      return true
    end
  end

  return false
end

local function state_file()
  return require("features.util.storage").path("state", "msvc_compile_databases.json")
end

local function edit_state(change)
  local f = assert(io.open(state_file(), "rb"))
  local data = vim.json.decode(f:read("*a"))

  f:close()
  for _, record in pairs(data) do
    change(record)
  end

  vim.fn.writefile({ vim.json.encode(data) }, state_file())
end

local INFO, WARN, ERROR = vim.log.levels.INFO, vim.log.levels.WARN, vim.log.levels.ERROR
local root = vim.fs.normalize(assert(os.getenv("MSVC_COMPILE_DATABASE_TEST_ROOT")))
local machine_is_x64 = (uv.os_uname().machine or ""):lower() == "x86_64"

-- 1. A .sln under a directory named with a space, Korean and "&".
local sln = vim.fs.joinpath(root, "한글 & space", "sln")

solution(sln, "sln")

local said = generate({ dir = vim.fs.joinpath(sln, "app") })
local db = read_database(sln)

check(said.level == INFO, ".sln: a database with nothing to report: " .. said.message)
check(db ~= nil and #db == 3, ".sln: an entry for each of the three sources")

local main = entry_of(db, "main.cpp") or { arguments = {} }

-- The directory as MSBuild spells it: long names, backslashes.
local function include_switch(dir)
  return "/I" .. (uv.fs_realpath(vim.fs.joinpath(dir, "Include")) or ""):gsub("/", "\\")
end

check(
  has(main.arguments, include_switch(sln)),
  ".sln: $(SolutionDir)Include is the solution's directory: " .. include_switch(sln)
)

check(has(main.arguments, 'FIXTURE_TEXT="a b"'), ".sln: a definition with quotes and a space is one argument")
check(entry_of(db, "util.c") ~= nil and entry_of(db, "lib.cpp") ~= nil, ".sln: the C file and the library's file")

local stray, missing, imsvc = false, false, 0

for _, entry in ipairs(db or {}) do
  for n, arg in ipairs(entry.arguments) do
    stray = stray or arg:find("^[/-]external:W[1-4]$") ~= nil
    if arg == "/imsvc" then
      imsvc = imsvc + 1
      missing = missing or not uv.fs_stat(entry.arguments[n + 1])
    end
  end
end

check(not stray, ".sln: no /external:W1..W4 (clang-cl would read -Wsystem-headers)")
check(imsvc > 0 and not missing, ".sln: the project's system include directories, each one existing")
check(
  main.arguments[1] ~= nil and (main.arguments[1] == "cl.exe" or uv.fs_stat(main.arguments[1]) ~= nil),
  ".sln: the compiler named is cl.exe or an existing file"
)

if machine_is_x64 then
  check(said.message:find("Debug|x64", 1, true) ~= nil, ".sln: Debug|x64 on an x64 machine, unasked")
  check(
    has(main.arguments, "--target=amd64-pc-windows-msvc"),
    ".sln: the clang target Microsoft's targets name for x64"
  )
end

same(database.complete("MsvcCompileDb "), {}, "completion: nothing without a buffer of the project")

local buf = vim.fn.bufadd(vim.fs.joinpath(sln, "app", "main.cpp"))

vim.api.nvim_set_current_buf(buf)
same(database.complete("MsvcCompileDb "), { "Debug", "Release" }, "completion: the solution's configurations")
same(database.complete("MsvcCompileDb Debug "), { "x64", "x86" }, "completion: that configuration's platforms")

-- The command as lua/plugins/lang/c.lua defines it.
for _, spec in ipairs(require("plugins.lang.c")) do
  if spec[1] == "msvc_compile_database" then
    spec.config()
  end
end

same(vim.fn.getcompletion("MsvcCompileDb r", "cmdline"), { "Release" }, ":MsvcCompileDb completes what is typed")
same(
  vim.fn.getcompletion("MsvcCompileDb Release ", "cmdline"),
  { "x64", "x86" },
  ":MsvcCompileDb completes the platform"
)

-- 2. The solution's x86 is the projects' Win32.
said = generate({ dir = vim.fs.joinpath(sln, "app"), configuration = "Debug", platform = "x86" })
db = read_database(sln)
main = entry_of(db, "main.cpp") or { arguments = {} }
check(said.level == INFO and said.message:find("Debug|x86", 1, true) ~= nil, "Debug|x86: " .. said.message)
check(has(main.arguments, "--target=i686-pc-windows-msvc"), "Debug|x86: the projects are read as Win32")

-- 3. What the solution has not.
local before = uv.fs_stat(vim.fs.joinpath(sln, "compile_commands.json"))

said = generate({ dir = vim.fs.joinpath(sln, "app"), configuration = "Debug", platform = "ARM64" })
check(
  said.level == ERROR and said.message:find("It has: Debug|x64, Debug|x86, Release|x64, Release|x86", 1, true) ~= nil,
  "a configuration the solution has not: an error that lists what it has"
)

local after = uv.fs_stat(vim.fs.joinpath(sln, "compile_commands.json"))

check(
  before and after and before.mtime.nsec == after.mtime.nsec and before.size == after.size,
  "and the database stays"
)

-- 4. Opening a file: rebuilt only when behind.
said = generate({ dir = vim.fs.joinpath(sln, "app"), configuration = "Debug", platform = "x64" })
check(said.level == INFO, "back to Debug|x64: " .. said.message)

-- What opening a file of the project does: nil when it runs nothing, what it said when it ran, and
-- { quiet = true } for a run that had nothing to tell.
local function opened()
  local count = #told

  database.forget()
  database.ensure(buf)
  if not database._busy() then
    return nil
  end

  vim.wait(600000, function()
    return not database._busy()
  end, 20)

  vim.wait(300, function()
    return #told > count
  end, 20)

  return #told > count and told[#told] or { quiet = true }
end

check(opened() == nil, "opening a file of a current database runs nothing")

local function identity(path)
  local st = uv.fs_stat(path)

  return st and ("%d %d %d"):format(st.ino, st.mtime.sec, st.mtime.nsec)
end

local sln_db = vim.fs.joinpath(sln, "compile_commands.json")
local written = identity(sln_db)

said = generate({ dir = vim.fs.joinpath(sln, "app") })
check(
  said.level == INFO and said.message:find("says the same as before", 1, true) ~= nil and identity(sln_db) == written,
  "asked again with nothing changed: the file is left as it is, and that is said: " .. said.message
)

edit_state(function(record)
  record.format = 1
end)

local renewed = opened()

check(
  renewed ~= nil and renewed.quiet and identity(sln_db) == written,
  "a record written the older way is renewed on opening a file, with nothing said for a database that says the same"
)

check(opened() == nil, "and is current again")

edit_state(function(record)
  record.toolchain.listings[1].mtime = 1
end)

check(opened() ~= nil, "a toolset or SDK directory that changed since: rebuilt")

edit_state(function(record)
  table.insert(record.toolchain.directories, vim.fs.joinpath(root, "no such toolset", "include"))
end)

check(opened() ~= nil, "a system include directory that is gone: rebuilt")

local stamp = vim.fs.joinpath(sln, "app", "app.vcxproj")

uv.fs_utime(stamp, os.time() + 10, os.time() + 10)
check(opened() ~= nil, "a project file changed since: rebuilt")

-- 5. A database someone else wrote is never replaced unasked.
local foreign = vim.fs.joinpath(root, "foreign")

solution(foreign, "sln")
write(vim.fs.joinpath(foreign, "compile_commands.json"), { "[]" })

local foreign_buf = vim.fn.bufadd(vim.fs.joinpath(foreign, "app", "main.cpp"))
local count = #told

database.forget()
database.ensure(foreign_buf)
vim.wait(1000)
check(
  #told == count and #read_database(foreign) == 0,
  "another tool's compile_commands.json: left alone, MSBuild not run"
)

-- 6. .slnx, the same solution.
local slnx = vim.fs.joinpath(root, "한글 & space", "slnx")

solution(slnx, "slnx")
said = generate({ dir = vim.fs.joinpath(slnx, "lib") })
db = read_database(slnx)
check(said.level == INFO and db ~= nil and #db == 3, ".slnx: " .. said.message)
check(
  has((entry_of(db, "lib.cpp") or {}).arguments, include_switch(slnx)),
  ".slnx: $(SolutionDir)Include is the solution's directory"
)

-- 7. What a machine may lack is said, not passed over.
local no_toolset = vim.fs.joinpath(root, "no toolset")

solution(no_toolset, "sln", { toolset = "v999" })
said = generate({ dir = vim.fs.joinpath(no_toolset, "app") })
check(
  said.level == WARN and said.message:find("platform toolset v999 is not installed", 1, true) ~= nil,
  "a toolset that is not installed is named: " .. said.message
)

local no_sdk = vim.fs.joinpath(root, "no sdk")

solution(no_sdk, "sln", { sdk = "10.0.1.0" })
said = generate({ dir = vim.fs.joinpath(no_sdk, "app") })
check(
  said.level == WARN and said.message:find("MSB8036", 1, true) ~= nil,
  "a Windows SDK version that is not installed: MSBuild's own error is shown: " .. said.message
)

local broken = vim.fs.joinpath(root, "broken")

solution(broken, "sln")
write(vim.fs.joinpath(broken, "lib", "lib.vcxproj"), { "<Project>", "  <This is not XML", "</Project>" })
said = generate({ dir = vim.fs.joinpath(broken, "app") })
db = read_database(broken)
check(
  said.level == WARN and said.message:find("lib.vcxproj", 1, true) ~= nil and db ~= nil and #db == 2,
  "a project MSBuild cannot read costs its own entries only, and is named: " .. said.message
)

-- 8. clangd reads a source of the first solution without an error.
local clangd = os.getenv("MSVC_COMPILE_DATABASE_TEST_CLANGD") or ""

if clangd == "" then
  print("SKIP clangd on the generated database: no clangd found")
else
  local published

  vim.bo[buf].filetype = "cpp"
  vim.fn.bufload(buf)
  vim.lsp.start({
    name = "clangd",
    cmd = { clangd, "--background-index=0", "--log=error" },
    root_dir = sln,
    handlers = {
      ["textDocument/publishDiagnostics"] = function(_, result)
        published = result.diagnostics
      end,
    },
  }, { bufnr = buf })

  vim.wait(120000, function()
    return published ~= nil
  end, 50)

  local errors = vim.tbl_filter(function(diagnostic)
    return diagnostic.severity == vim.lsp.protocol.DiagnosticSeverity.Error
  end, published or {})

  check(published ~= nil, "clangd answered for app/main.cpp")
  check(
    #errors == 0,
    ("clangd: no error in app/main.cpp (<Windows.h>, shared.h from $(SolutionDir)Include, the quoted definition)%s"):format(
      errors[1] and (": " .. errors[1].message) or ""
    )
  )

  check(#(published or {}) == 0, ("clangd: no other diagnostic either: %s"):format(vim.inspect(published)))
  for _, client in ipairs(vim.lsp.get_clients()) do
    client:stop()
  end
end

print(("== %d failed"):format(failures))
vim.cmd.cquit(failures == 0 and 0 or 1)
