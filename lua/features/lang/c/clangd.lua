-- What clangd needs from this configuration beyond its flags: a private temporary directory per Neovim, and on
-- Windows the compilers it may ask for their target and system includes.
local M = {}

-- clangd's preambles and other temporary files, in a 0700 directory of this Neovim that goes when it exits; the
-- directories of Neovims that are gone are removed on the way. Each is named <host>-<pid>: on a home that several
-- machines share, another machine's process ids say nothing here, and its live directories stay.
function M.private_tmp()
  local base = require("features.util.storage").path("cache", "clangd_temporary_files")
  local host = (vim.uv.os_gethostname() or "host"):gsub("[^%w.-]", "_") .. "-"

  for name in vim.fs.dir(base) do
    -- A name of the process id alone is from before hosts were named.
    local pid = tonumber(name:sub(1, #host) == host and name:sub(#host + 1) or name)

    -- Only ESRCH means gone; EPERM is a live Neovim this user may not signal.
    if pid and pid ~= vim.fn.getpid() and select(3, vim.uv.kill(pid, 0)) == "ESRCH" then
      pcall(vim.fs.rm, vim.fs.joinpath(base, name), { recursive = true, force = true })
    end
  end

  local dir = vim.fs.joinpath(base, host .. vim.fn.getpid())

  ---@diagnostic disable-next-line: param-type-mismatch
  vim.fn.mkdir(dir, "p", tonumber("700", 8))
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("clangd_temporary_files", { clear = true }),
    callback = function()
      pcall(vim.fs.rm, dir, { recursive = true, force = true })
    end,
  })

  return dir
end

-- Windows: clangd assumes an MSVC target and its headers. A compile database written for MinGW's gcc (or a clang on
-- PATH) needs clangd to ask that compiler for its target and system includes, and clangd runs whichever allowed
-- driver the database names, with the database's own -specs, --sysroot and -target: a gcc -specs file can make gcc
-- run any program. So it is off unless vim.g.clangd_query_driver is true (for trusted projects), and then allows only
-- the .exe of each compiler on PATH by its exact path; a directory glob would also allow its neighbours (cmake's
-- cpack, a .bat) and, on Windows, a path that leaves the directory through "..".
function M.query_driver()
  if vim.g.clangd_query_driver ~= true then
    return nil
  end

  local drivers, seen = {}, {}
  -- PATH's own entries only: with cmd.exe as 'shell', exepath() also finds a compiler in the current directory,
  -- which a repository could put there.
  local on_path = {}

  for _, entry in ipairs(require("features.util.path_variable").directories(vim.env.PATH)) do
    local dir = vim.fs.normalize(entry, { expand_env = false }):gsub("/+$", "")

    if vim.fn.isabsolutepath(dir) == 1 then
      on_path[dir:lower()] = true
    end
  end

  for _, name in ipairs({ "gcc", "g++", "cc", "c++", "clang", "clang++" }) do
    local path = vim.fn.exepath(name)

    -- The file's own spelling (exepath() writes the extension as PATHEXT does, .EXE): clangd compares it as given.
    local real = path ~= "" and vim.uv.fs_realpath(path)

    if real and real:lower():find("%.exe$") then
      local exe = vim.fs.normalize(real)

      if on_path[vim.fs.dirname(exe):lower()] and not seen[exe:lower()] and not exe:find("[,*?%[%]{}]") then
        seen[exe:lower()] = true
        drivers[#drivers + 1] = exe
      end
    end
  end

  return #drivers > 0 and ("--query-driver=" .. table.concat(drivers, ",")) or nil
end

return M
