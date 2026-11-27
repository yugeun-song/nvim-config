-- Windows only: how this repository's native programs (native/*.c) are built, for the code that builds them
-- (ime_helper.lua, wsl_bridge.lua). Visual Studio's cl (MSVC) compiles them; clang targeting MSVC reads them only
-- in their tests' static checks (tests/<program>/run.ps1).
local M = {}

local uv = vim.uv

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

return M
