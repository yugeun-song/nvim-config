-- ghcup's bin directory, added at the end of PATH when Haskell is first needed (a Haskell buffer, :checkhealth):
-- ghcup installs there (https://www.haskell.org/ghcup/install/: ~/.ghcup/bin, C:\ghcup\bin on Windows) without the
-- environment Neovim started from always knowing. GHCUP_INSTALL_BASE_PREFIX, ghcup's variable for its base, moves it.
local M = {}

local WIN = vim.fn.has("win32") == 1
local added = false

function M.bin_directory()
  local base = vim.env.GHCUP_INSTALL_BASE_PREFIX

  if base and base ~= "" then
    return vim.fs.joinpath(base, WIN and "ghcup" or ".ghcup", "bin")
  end

  return WIN and "C:/ghcup/bin" or vim.fs.joinpath(vim.uv.os_homedir() or "", ".ghcup", "bin")
end

function M.add_to_path()
  if added then
    return
  end

  added = true

  local bin = M.bin_directory()

  if not vim.uv.fs_stat(bin) then
    return
  end

  local sep = WIN and ";" or ":"
  local wanted = vim.fs.normalize(bin)

  for dir in vim.gsplit(vim.env.PATH or "", sep, { plain = true, trimempty = true }) do
    local have = vim.fs.normalize(dir)

    if (WIN and have:lower() == wanted:lower()) or have == wanted then
      return
    end
  end

  vim.env.PATH = (vim.env.PATH or "") .. sep .. bin
end

return M
