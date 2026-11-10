-- Modified from https://github.com/LazyVim/starter (Apache-2.0). See THIRD-PARTY-NOTICES.
-- LazyVim refuses Neovim before 0.11.2; 0.11 starts with a notice.
if vim.fn.has("nvim-0.12") == 0 then
  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    once = true,
    callback = function()
      vim.notify(
        ("Neovim %s: this configuration needs 0.12, and some features fail. :checkhealth config"):format(
          tostring(vim.version())
        ),
        vim.log.levels.WARN,
        { title = "nvim-config" }
      )
    end,
  })
end

-- Windows: executable() and exepath() remember their answers
-- (lua/features/util/windows/executable_lookup_cache.lua), and Visual Studio's MSVC environment is set as a
-- Developer Prompt would (lua/features/lang/c/msvc_toolchain/developer_environment.lua).
if vim.fn.has("win32") == 1 then
  require("features.util.windows.executable_lookup_cache").install()
  require("features.lang.c.msvc_toolchain.developer_environment").setup()
end

-- Programs registered by path (<leader>uX): one stat when none is, the module only when one is.
if vim.uv.fs_stat(require("features.util.storage").path("state", "registered_programs.json")) then
  require("features.util.tool_paths").setup()
end

require("features.editor.open_folder").startup()
require("features.editor.open_in_running_instance").setup()
require("features.ui.terminal_background").setup()

-- The first start after :ManagedPathsReset says what it did, or why it did nothing, once the UI is up. One stat
-- at every start; the module loads only when the reset left its flag.
if vim.uv.fs_stat(require("features.util.storage").path("state", "reset_report_unread")) then
  pcall(function()
    require("features.util.managed_paths").announce_report()
  end)
end

require("config.lazy")
