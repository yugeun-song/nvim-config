-- What clangd needs from this configuration beyond its flags: a private temporary directory per Neovim, and on
-- Windows the compilers it may ask for their target and system includes.
local M = {}

-- clangd's preambles and other temporary files, in a 0700 directory of this Neovim that goes when it exits; the
-- directories of Neovims that are gone are removed on the way.
function M.private_tmp()
  local base = require("features.util.storage").path("cache", "clangd_temporary_files")

  for name in vim.fs.dir(base) do
    local pid = tonumber(name)

    -- Only ESRCH means gone; EPERM is a live Neovim this user may not signal.
    if pid and pid ~= vim.fn.getpid() and select(3, vim.uv.kill(pid, 0)) == "ESRCH" then
      pcall(vim.fs.rm, vim.fs.joinpath(base, name), { recursive = true, force = true })
    end
  end

  local dir = vim.fs.joinpath(base, tostring(vim.fn.getpid()))

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

-- Windows: clangd assumes an MSVC target and its headers. A compile database written for MinGW's gcc (or a
-- clang on PATH) needs clangd to ask that compiler for its target and system includes, which it does only for
-- drivers in this allowlist: the directories the compilers on PATH live in, so nothing a repository names runs.
function M.query_driver()
  local dirs, seen = {}, {}
  -- PATH's own entries only: with cmd.exe as 'shell', exepath() also finds a compiler in the current directory,
  -- which a repository could put there.
  local on_path = {}

  for entry in (vim.env.PATH or ""):gmatch("[^;]+") do
    local dir = vim.fs.normalize(entry):gsub("/+$", "")

    if vim.fn.isabsolutepath(dir) == 1 then
      on_path[dir:lower()] = true
    end
  end

  for _, name in ipairs({ "gcc", "g++", "cc", "c++", "clang", "clang++" }) do
    local path = vim.fn.exepath(name)

    if path ~= "" then
      local dir = vim.fs.dirname(vim.fs.normalize(path))

      if on_path[dir:lower()] and not seen[dir:lower()] then
        seen[dir:lower()] = true
        dirs[#dirs + 1] = dir .. "/*"
      end
    end
  end

  return #dirs > 0 and ("--query-driver=" .. table.concat(dirs, ",")) or nil
end

return M
