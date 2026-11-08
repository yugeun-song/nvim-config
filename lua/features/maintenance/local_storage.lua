-- Where this configuration keeps what it writes for itself: one directory named after it inside each of Neovim's
-- own (stdpath data, state, cache, run), which no plugin writes to. Every file it keeps there is listed below with
-- what it holds; :ManagedPaths shows them, and the configuration's own reset removes these directories and nothing
-- else. A file from the older layout (directly in stdpath, under its old name) moves here the first time its
-- owner asks for it; one that cannot move (a running program's directory on Windows) stays, listed as left over.
local M = {}

local uv = vim.uv

M.NAME = "nvim-config"

-- kind, name here, name it had directly in stdpath(kind) before (false: none), what it holds
M.ENTRIES = {
  { "state", "registered_programs.json", "tools.json", "programs registered by path (<leader>uX, :ToolPath)" },
  { "state", "windows_program_discovery.json", "tool_discovery.json", "programs <leader>uX found (Windows)" },
  { "state", "mason_install_failures.json", "mason-failed.json", "Mason installs held back after a failure" },
  { "state", "msvc_developer_environment.json", "msvc_env.json", "the MSVC environment VsDevCmd sets (Windows)" },
  { "state", "msvc_compile_databases.json", "msvc_compiledb.json", "databases :MsvcCompileDb wrote (Windows)" },
  { "state", "all_ifdef_branches", "ifdef_all", "the all-#if-branches view, on or off (<leader>uB)" },
  { "state", "open_folder_history", "open_folder_history", "folders opened (Projects)" },
  { "state", "colorscheme_choice", "colorscheme", "the default colorscheme confirmed in <leader>uC" },
  { "state", "reset_report.txt", "reset-report.txt", "what the last reset removed" },
  { "state", "reset_report_unread", false, "the last reset's report, until a start has shown it" },
  { "state", "reset_confirmation", "reset-confirmed", 'the confirmation a typed "reset" leaves for the reset' },
  { "state", "running_instances", "nvim-focus", "running Neovims with a UI, for scripts/open-at.lua" },
  { "run", "running_instances", "nvim-focus", "running Neovims with a UI, for scripts/open-at.lua" },
  { "data", "windows_ime_helper", "winctl", "the Windows IME helper, built here from native/windows_ime_helper.c" },
  { "data", "registered_program_shims", "shims", "one shim per registered program; last on PATH in Neovim" },
  { "data", "language_server_attach_rules.json", "lsp_filter/rules.json", "language server attach rules (<leader>cF)" },
  { "data", "alive_lsp", "alive-lsp", "the Common Lisp language server and its libraries" },
  { "cache", "executable_lookup_cache.json", "which.json", "executable() and exepath() answers per PATH (Windows)" },
  { "cache", "clangd_temporary_files", "clangd-tmp", "clangd's temporary files, one directory per Neovim" },
}

M.KINDS = { "data", "state", "cache", "run" }

-- Read on the main loop: path() is called from libuv callbacks too, where no Vimscript function may run. "run" is
-- read when first asked for, since asking makes Neovim create it.
local base = {}

-- stdpath("run") is XDG_RUNTIME_DIR itself, shared by every NVIM_APPNAME (the other kinds are not): the app name
-- keeps each one's running instances apart.
local APP = os.getenv("NVIM_APPNAME")

APP = APP ~= nil and APP ~= "" and APP or "nvim"

for _, kind in ipairs({ "data", "state", "cache" }) do
  base[kind] = vim.fs.normalize(vim.fn.stdpath(kind))
end

local function base_of(kind)
  if not base[kind] and kind == "run" then
    base.run = vim.fs.normalize(vim.fn.stdpath("run"))
  end

  return assert(base[kind], "no such stdpath kind: " .. tostring(kind))
end

local function make_directories(dir)
  if uv.fs_stat(dir) then
    return
  end

  make_directories(vim.fs.dirname(dir))
  uv.fs_mkdir(dir, 493) -- 0755
end

local by_name = {}

for _, entry in ipairs(M.ENTRIES) do
  by_name[entry[1] .. "/" .. entry[2]] = entry
end

local made = {}

-- This configuration's directory inside stdpath(kind), not created: for "run", one per NVIM_APPNAME inside it.
function M.location(kind)
  local dir = vim.fs.joinpath(base_of(kind), M.NAME)

  return kind == "run" and vim.fs.joinpath(dir, APP) or dir
end

-- This configuration's directory inside stdpath(kind), created the first time it is asked for.
function M.dir(kind)
  local dir = M.location(kind)

  if not made[kind] then
    make_directories(dir)
    made[kind] = true
  end

  return dir
end

-- The path of name (a file or directory listed above, or a passing one such as a socket) in this configuration's
-- directory of that kind. A listed one still in its old place moves here first.
function M.path(kind, name)
  local path = vim.fs.joinpath(M.dir(kind), name)
  local entry = by_name[kind .. "/" .. name]

  if entry and entry[3] and not uv.fs_stat(path) then
    -- Where the old name may be: directly in stdpath(kind), or already in this directory under it (a rename that
    -- came after the move here, as winctl's to windows_ime_helper).
    local old = vim.fs.joinpath(base_of(kind), entry[3])

    if not uv.fs_stat(old) and entry[3] ~= name then
      old = vim.fs.joinpath(M.dir(kind), entry[3])
    end

    if uv.fs_stat(old) then
      make_directories(vim.fs.dirname(path))

      if uv.fs_rename(old, path) then
        -- An old file kept in a directory of its own (lsp_filter/rules.json) leaves that directory empty.
        local parent = vim.fs.dirname(old)

        if parent ~= base_of(kind) then
          uv.fs_rmdir(parent)
        end
      end
    end
  end

  return path
end

-- The old names, as they would be found directly in stdpath(kind): what an older layout left there.
function M.old_names(kind)
  local names = {}

  for _, entry in ipairs(M.ENTRIES) do
    if entry[1] == kind and entry[3] then
      names[(entry[3]:match("^[^/]+"))] = entry[4]
    end
  end

  return names
end

return M
