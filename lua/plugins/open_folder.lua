local yazi = vim.fn.executable("yazi") == 1

local function pick()
  require("open_folder").pick()
end

local function projects()
  Snacks.picker.projects({
    projects = require("open_folder").recent(),
    confirm = function(picker, item)
      picker:close()
      if item then
        require("open_folder").open(item.file)
      end
    end,
  })
end

local keys = { { "<leader>fp", projects, desc = "Projects" } }
if yazi then
  table.insert(keys, { "<leader>fo", pick, desc = "Open Folder" })
end

return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    local items = opts.dashboard.preset.keys
    for _, item in ipairs(items) do
      if item.key == "p" then
        item.action = projects
      end
    end
    if yazi then
      table.insert(items, 1, { icon = "\u{f07c} ", key = "o", desc = "Open Folder", action = pick })
    end
  end,
  keys = keys,
}
