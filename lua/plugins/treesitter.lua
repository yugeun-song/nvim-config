-- Windows: nvim-treesitter updates a parser by renaming <lang>.so to <lang>.so<hrtime> and deleting that, but Windows
-- cannot delete a DLL a running Neovim has loaded, so the copy stays. An hrtime past 1e14 (about 28 hours of uptime)
-- prints as "2.96e+14", and nvim-treesitter then lists the copy as the language "<lang>.so2", which every :TSUpdate
-- fails to find. Each start deletes, in the background, the copies no Neovim holds any more.
local function remove_replaced_parsers()
  local dir = require("nvim-treesitter.config").get_install_dir("parser")

  vim.uv.fs_scandir(dir, function(err, handle)
    if err or not handle then
      return
    end

    while true do
      local name, kind = vim.uv.fs_scandir_next(handle)

      if not name then
        break
      end

      -- Only nvim-treesitter's renamed copies: a language name, ".so", then the hrtime it printed.
      if kind ~= "directory" and name:match("^[%w_]+%.so%d[%d%.e%+]*$") then
        -- One a running Neovim still holds stays until a later start.
        vim.uv.fs_unlink(dir .. "/" .. name, function() end)
      end
    end
  end)
end

return {
  "nvim-treesitter/nvim-treesitter",
  -- A function, not init: lazy.nvim keeps one init per plugin, and lua/plugins/lang/asm.lua has nvim-treesitter's.
  -- Each spec's opts function runs; the sweep is scheduled after LazyVim's setup has set the install directory.
  opts = function(_, opts)
    -- Parsers of the languages without a file in lua/plugins/lang/, which add their own. LazyVim installs its
    -- own list too (c, bash, lua, markdown, python, ...); the lists are joined.
    opts.ensure_installed = opts.ensure_installed or {}
    vim.list_extend(opts.ensure_installed, {
      "awk",
      "css",
      "dockerfile",
      "erlang",
      "git_config",
      "git_rebase",
      "gitattributes",
      "gitcommit",
      "java",
      "julia",
      "kconfig",
      "kotlin",
      "make",
    })

    if vim.fn.has("win32") == 1 then
      vim.schedule(remove_replaced_parsers)
    end
  end,
}
