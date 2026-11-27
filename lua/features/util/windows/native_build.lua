-- Windows only: how this repository's native programs (native/*.c) are built, for the code that builds them
-- (ime_helper.lua, wsl_bridge.lua) and for clangd. Visual Studio's cl (MSVC) compiles them; clang targeting MSVC
-- reads them only in their tests' static checks (tests/<program>/run.ps1).
local M = {}

local uv = vim.uv

-- The repository is what comes before this file's lua/ directory, at whatever depth the module sits.
M.REPOSITORY = vim.fs.normalize(debug.getinfo(1, "S").source:sub(2)):match("^(.*)/lua/")
  or vim.fs.normalize(vim.fn.stdpath("config"))

-- argv[0] of the commands clangd gets: the name makes clangd read the switches as cl's. clangd never runs it.
local CLANGD_DRIVER = "cl.exe"

-- tests/<program>/*.c as tests/<program>/run.ps1 compiles each; every one includes native/<program>.c.
local TEST_SWITCHES = {
  ["unit.c"] = { "/nologo", "/W4", "/fsanitize=address", "/Zi", "/Od" },
  ["fuzz.c"] = { "/nologo", "/W3", "/fsanitize=fuzzer", "/fsanitize=address", "/Zi", "/Od" },
}

-- The cl of the toolset the MSVC environment names (Neovim's, from a Developer prompt or the captured one in
-- lua/features/lang/c/msvc_toolchain/developer_environment.lua), by its full path: PATH can list folders other
-- users may write before the toolset's own.
function M.cl_in_toolset()
  local dir = uv.os_getenv("VCToolsInstallDir")

  if not dir or dir == "" then
    return nil
  end

  local host = (uv.os_uname().machine or ""):lower():find("arm") and "Hostarm64" or "Hostx64"
  local cl = vim.fs.joinpath(dir, "bin", host, "x64", "cl.exe")
  local st = uv.fs_stat(cl)

  return st and st.type == "file" and cl or nil
end

-- The compilers that build SRC, in the order they are tried: cl only. Warnings fail the build (/WX), the linker's
-- too: a library for another machine is only a warning otherwise. The C runtime is linked in, so the program loads
-- no DLL but the system's own. version is what the program's `version` names its compiler.
---@param src string
function M.compilers(src)
  return {
    {
      name = "cl",
      version = "msvc",
      locate = M.cl_in_toolset,
      args = function(out, program)
        return {
          program,
          "/nologo",
          -- The object beside the build's own temporary .exe: another Neovim may be building at the same time.
          "/Fo" .. out:sub(1, -5) .. ".obj",
          "/O2",
          "/MT",
          "/W4",
          "/WX",
          "/sdl",
          "/guard:cf",
          "/Fe" .. out,
          src,
          "/link",
          "/WX",
          "/guard:cf",
          "/DEPENDENTLOADFLAG:0x800",
          "/CETCOMPAT",
        }
      end,
    },
  }
end

-- cl's compile switches for SRC as the build passes them, without its outputs, the source and the linker's part.
local function compile_switches(src)
  local args = M.compilers(src)[1].args("OUT.exe", CLANGD_DRIVER)
  local switches = {}

  for i = 2, #args do
    local arg = args[i]

    if arg == "/link" then
      break
    end

    if arg ~= src and not arg:find("^/F[eo]") then
      switches[#switches + 1] = arg
    end
  end

  return switches
end

-- Whether a clangd rooted at ROOT serves this repository: its root is the repository or a directory in it
-- (native/ is a root of its own, as its .clang-format is a root marker).
---@param root string?
function M.serves(root)
  if not root or root == "" then
    return false
  end

  local function spelled(path)
    return vim.fs.normalize(uv.fs_realpath(path) or path):lower()
  end

  return vim.fs.relpath(spelled(M.REPOSITORY), spelled(root)) ~= nil
end

-- The command that builds each native program and each of its tests, keyed by file, in the form clangd's
-- compilationDatabaseChanges takes. A program's tests are the .c files in tests/<program>/.
---@return table<string, { workingDirectory: string, compilationCommand: string[] }>
function M.clangd_commands()
  local commands = {}

  local function add(file, switches)
    local command = vim.list_extend({ CLANGD_DRIVER }, switches)

    command[#command + 1] = file
    commands[file] = { workingDirectory = M.REPOSITORY, compilationCommand = command }
  end

  local native = vim.fs.joinpath(M.REPOSITORY, "native")

  for name, kind in vim.fs.dir(native) do
    local program = kind == "file" and name:match("^(.+)%.c$")

    if program then
      local src = vim.fs.joinpath(native, name)
      local switches = compile_switches(src)
      local tests = vim.fs.joinpath(M.REPOSITORY, "tests", program)

      add(src, switches)
      for test, test_kind in vim.fs.dir(tests) do
        if test_kind == "file" and test:match("%.c$") then
          add(vim.fs.joinpath(tests, test), TEST_SWITCHES[test] or switches)
        end
      end
    end
  end

  return commands
end

return M
