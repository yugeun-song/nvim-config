-- Discord Rich Presence (lua/features/util/discord_rich_presence.lua): :DiscordRpcToggle, <leader>uP.
return {
  "discord_rich_presence",
  virtual = true,
  -- Every session, without a key or a file to wait for, and nothing on the first screen needs it.
  event = "VeryLazy",
  config = function()
    require("features.util.discord_rich_presence").setup()
  end,
}
