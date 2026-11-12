-- Notifications wrap. Snacks cuts each line at the notification's width (40 % of the screen), and this
-- configuration's messages end in what to do about them.
return {
  "folke/snacks.nvim",
  opts = { styles = { notification = { wo = { wrap = true } } } },
}
