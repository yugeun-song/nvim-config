-- Windows: Mason installs no package whose runtime is missing (Java, Elixir, Erlang, Julia), nor one whose install
-- failed lately (lua/features/external_programs/mason_windows_install_gate.lua). Runs when Mason loads, after
-- lua/plugins/external_programs/mason_packages.lua's list is merged; what is installed stays.
if vim.fn.has("win32") == 0 then
  return {}
end

return {
  "mason-org/mason.nvim",
  opts = function(_, opts)
    local held = require("features.external_programs.mason_windows_install_gate")

    opts.ensure_installed = held.filter(opts.ensure_installed or {})
    held.track()
  end,
}
