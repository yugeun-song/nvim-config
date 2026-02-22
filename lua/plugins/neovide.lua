if vim.g.neovide then
  vim.o.guifont = "CaskaydiaCove_Nerd_Font:h12"

  vim.g.neovide_refresh_rate = 120
  vim.g.neovide_refresh_rate_idle = 5

  vim.g.neovide_cursor_vfx_mode = ""
  vim.g.neovide_cursor_animation_length = 0.05
  vim.g.neovide_cursor_trail_size = 50.0
  vim.g.neovide_cursor_antialiasing = true

  vim.o.guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor"

  vim.g.neovide_opacity = 1.0
  vim.g.neovide_floating_blur_amount_x = 0.0
  vim.g.neovide_floating_blur_amount_y = 0.0
  vim.g.neovide_confirm_quit = true
end

return {}
