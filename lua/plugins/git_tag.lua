if vim.fn.executable("git") ~= 1 then
  return {}
end

local uv = vim.uv or vim.loop
if not uv then
  return {}
end

local ICON = ""
local TTL_MS = 10000
local FALLBACK_FG = "#5ccc96"

local roots = {}
local tags = {}
local fg

local function repo_root(dir)
  if dir == nil or dir == "" then
    return nil
  end

  local hit = roots[dir]
  if hit ~= nil then
    return hit or nil
  end

  local marker = vim.fs.find(".git", { path = dir, upward = true, limit = 1 })[1]
  local root = marker and vim.fs.dirname(marker) or false
  roots[dir] = root
  return root or nil
end

local function parse(raw)
  if raw == "" then
    return false
  end

  local tag, ahead = raw:match("^(.*)%-(%d+)%-g%x+$")
  if not tag then
    return raw
  end
  if ahead == "0" then
    return tag
  end
  return tag .. "+" .. ahead
end

local function refresh(root)
  local entry = tags[root]
  if entry.running then
    return
  end
  entry.running = true

  local lines = {}
  local job = vim.fn.jobstart({ "git", "-C", root, "describe", "--tags", "--long" }, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        lines = data
      end
    end,
    on_exit = function(_, code)
      entry.running = false
      entry.stamp = uv.now()

      local label = false
      if code == 0 then
        local raw = table.concat(lines, ""):gsub("%s", "")
        label = parse(raw)
      end

      if entry.label ~= label then
        entry.label = label
        vim.schedule(function()
          pcall(vim.cmd.redrawstatus)
        end)
      end
    end,
  })

  if job <= 0 then
    entry.running = false
    entry.stamp = uv.now()
  end
end

local function buffer_dir()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then
    return uv.cwd()
  end

  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or name:find("://") then
    return uv.cwd()
  end

  return vim.fs.dirname(vim.fn.fnamemodify(name, ":p"))
end

local function git_tag()
  local ok, result = pcall(function()
    local root = repo_root(buffer_dir())
    if not root then
      return ""
    end

    local entry = tags[root]
    if not entry then
      entry = { running = false, label = false }
      tags[root] = entry
    end

    if not entry.running and (entry.stamp == nil or uv.now() - entry.stamp > TTL_MS) then
      refresh(root)
    end

    return entry.label and (ICON .. " " .. entry.label) or ""
  end)

  if not ok or type(result) ~= "string" then
    return ""
  end
  return result
end

local function tag_color()
  if not fg then
    local ok, color = pcall(function()
      return Snacks.util.color("String")
    end)
    fg = (ok and color) or FALLBACK_FG
  end
  return { fg = fg }
end

local group = vim.api.nvim_create_augroup("LualineGitTag", { clear = true })
vim.api.nvim_create_autocmd({ "FocusGained", "DirChanged" }, {
  group = group,
  callback = function()
    for _, entry in pairs(tags) do
      entry.stamp = nil
    end
  end,
})
vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = function()
    fg = nil
  end,
})

return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      local section = opts.sections and opts.sections.lualine_b
      if not section then
        return
      end

      table.insert(section, math.min(2, #section + 1), {
        git_tag,
        color = tag_color,
        padding = { left = 1, right = 1 },
      })
    end,
  },
}
