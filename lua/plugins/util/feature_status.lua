-- :FeatureStatus: every feature on this system, as available, not supported here, or blocked and why
-- (:checkhealth config, then each lua/features/*/health.lua).
return {
  "feature_status",
  virtual = true,
  cmd = "FeatureStatus",
  config = function()
    vim.api.nvim_create_user_command("FeatureStatus", function()
      vim.cmd("checkhealth config features.*")
    end, { desc = "Every feature: available, not supported here, or blocked and why" })
  end,
}
