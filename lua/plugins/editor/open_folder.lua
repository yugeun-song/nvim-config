local yazi = vim.fn.executable("yazi") == 1

local function pick()
  require("features.editor.open_folder").pick()
end

local function projects()
  local open_folder = require("features.editor.open_folder")
  local opened = open_folder.recent()
  local place = open_folder.place_in(opened)

  Snacks.picker.projects({
    projects = opened,
    -- The folders opened here first, the last one on top, then the ones Snacks finds (git roots of recent files).
    -- Snacks' frecency ranks a folder by the visits to files in it, which put a folder just opened at the bottom.
    matcher = { frecency = false },
    sort = { fields = { "score:desc", "opened", "idx" } },
    transform = function(item)
      item.opened = place(item.file) or math.huge
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        require("features.editor.open_folder").open(item.file, nil, { pick_files = true })
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
