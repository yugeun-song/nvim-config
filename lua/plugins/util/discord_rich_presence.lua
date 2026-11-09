-- Discord Rich Presence (lua/features/util/discord_rich_presence.lua): :DiscordRpcToggle, <leader>uP.
return {
  "discord_rich_presence",
  virtual = true,
  -- Discord sees the presence once the first screen is drawn; nothing before it needs it.
  event = "VeryLazy",
  config = function()
    require("features.util.discord_rich_presence").setup()
  end,
}
