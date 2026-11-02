if vim.g.neovide then
  vim.g.neovide_text_gamma = 1.5
  vim.g.neovide_text_contrast = 1.0
  vim.opt.linespace = 0
  vim.g.neovide_scale_factor = 1.0
  vim.g.neovide_refresh_rate = 120
  vim.g.neovide_refresh_rate_idle = 5
  vim.g.neovide_cursor_vfx_mode = ""
  vim.g.neovide_cursor_animation_length = 0.15
  vim.g.neovide_cursor_trail_size = 0.8
  vim.g.neovide_cursor_antialiasing = true
  vim.g.neovide_opacity = 1.0
  vim.g.neovide_floating_blur_amount_x = 0.0
  vim.g.neovide_floating_blur_amount_y = 0.0
  vim.g.neovide_confirm_quit = true
  vim.g.neovide_padding_top = 28
  vim.g.neovide_padding_bottom = 0
  vim.g.neovide_padding_right = 28
  vim.g.neovide_padding_left = 28

  -- Neovide stretches the last row into the sub-cell gap below it; keep that row an empty cmdline.
  vim.o.cmdheight = 1
  vim.api.nvim_create_autocmd("OptionSet", {
    pattern = "cmdheight",
    callback = function()
      if vim.o.cmdheight == 0 then
        vim.o.cmdheight = 1
      end
    end,
    desc = "Keep the empty cmdline row that noice's ext_messages attach removes",
  })

  local function scale(delta)
    vim.g.neovide_scale_factor = vim.g.neovide_scale_factor * delta
  end
  local zoom_modes = { "n", "i", "v", "c" }
  vim.keymap.set(zoom_modes, "<C-=>", function()
    scale(1.1)
  end)
  vim.keymap.set(zoom_modes, "<C-+>", function()
    scale(1.1)
  end)
  vim.keymap.set(zoom_modes, "<C-->", function()
    scale(1 / 1.1)
  end)
  vim.keymap.set(zoom_modes, "<C-0>", function()
    vim.g.neovide_scale_factor = 1.0
  end)

  local function paste()
    vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
  end
  vim.keymap.set({ "n", "i", "v", "c", "t" }, "<C-S-v>", paste, { silent = true, desc = "Paste from clipboard" })
end

return {}
