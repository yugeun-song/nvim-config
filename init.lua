-- Modified from https://github.com/LazyVim/starter (Apache-2.0). See THIRD-PARTY-NOTICES.
-- Windows: executable() and exepath() remember their answers
-- (lua/features/windows_platform/executable_lookup_cache.lua), and Visual Studio's MSVC environment is set as a
-- Developer Prompt would (lua/features/languages/c_and_cpp/msvc_toolchain/developer_environment.lua).
if vim.fn.has("win32") == 1 then
  require("features.windows_platform.executable_lookup_cache").install()
  require("features.languages.c_and_cpp.msvc_toolchain.developer_environment").setup()
end

-- Programs registered by path (<leader>uX): one stat when none is, the module only when one is.
if vim.uv.fs_stat(require("features.maintenance.local_storage").path("state", "registered_programs.json")) then
  require("features.external_programs.registered_programs").setup()
end

require("features.editing.open_folder").startup()
require("features.editing.open_in_running_instance").setup()
require("features.appearance.terminal_background").setup()
require("config.lazy")
