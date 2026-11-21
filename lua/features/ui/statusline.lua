-- The latest tag of the current git repository, in the statusline after the branch; read in the background and
-- kept for a while per repository.
local M = {}

local uv = vim.uv

local ICON = ""
local TTL_MS = 60000
local FALLBACK_FG = "#5ccc96"

local roots = {}
local tags = {}
local fg
local focused = true

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

    if focused and not entry.running and (entry.stamp == nil or uv.now() - entry.stamp > TTL_MS) then
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

local function watch()
  local group = vim.api.nvim_create_augroup("LualineGitTag", { clear = true })

  vim.api.nvim_create_autocmd({ "FocusGained", "DirChanged" }, {
    group = group,
    callback = function()
      focused = true
      for _, entry in pairs(tags) do
        entry.stamp = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd("FocusLost", {
    group = group,
    callback = function()
      focused = false
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      fg = nil
    end,
  })
end

-- Statusline code: %{expr}, %-N{expr} and %{%expr%} run Vimscript (system() included), %!expr does at the start of an
-- option, and %@Func@ calls Func on a click. The other items only format: an escaped % (%%), highlights (%#Group#,
-- %*, %N*), alignment (%=, %<), item groups (%(, %)) and tab page labels (%T, %X).
local FORMATS = { ["%"] = true, ["*"] = true, ["="] = true, ["<"] = true, T = true, X = true }
local RUNS = { ["{"] = true, ["!"] = true, ["@"] = true, [""] = true }

-- Components, plugin modules and functions already guarded here.
local guarded = setmetatable({}, { __mode = "k" })

-- Text shown as it is: every % doubled.
function M.escape(text)
  return type(text) == "string" and (text:gsub("%%", "%%%%")) or text
end

-- Statusline code with the items that run something turned into text, their % doubled; so is a % that ends the code,
-- which would join what follows it.
local function defuse(code)
  local out, i = {}, 1

  while true do
    local at = code:find("%", i, true)

    if not at then
      out[#out + 1] = code:sub(i)

      break
    end

    out[#out + 1] = code:sub(i, at - 1)

    if code:sub(at + 1, at + 1) == "%" then
      out[#out + 1] = "%%"
      i = at + 2
    else
      local flags = code:match("^[-0-9.]*", at + 1)

      out[#out + 1] = RUNS[code:sub(at + 1 + #flags, at + 1 + #flags)] and "%%" or "%"
      i = at + 1
    end
  end

  return table.concat(out)
end

-- Whether every % of text starts one of the items above, each %#Group# and %( closed: code a component builds. Text
-- with any other % in it (a git tag v2%=%{%x%}, a folder 50%off) is no such code, and lualine fails on it (E539, E542).
local function is_code(text)
  local depth, i = 0, 1

  while true do
    local at = text:find("%", i, true)

    if not at then
      return depth == 0
    end

    local flags = text:match("^[-0-9.]*", at + 1)
    local item = text:sub(at + 1 + #flags, at + 1 + #flags)

    i = at + 2 + #flags
    if item == "#" then
      local close = text:find("#", i, true)

      if not close then
        return false
      end

      i = close + 1
    elseif item == "(" or item == ")" then
      depth = depth + (item == "(" and 1 or -1)
      if depth < 0 then
        return false
      end
    elseif not (FORMATS[item] or RUNS[item]) then
      return false
    end
  end
end

-- What a component shows, safe in 'statusline'. Code a component builds on purpose (trouble's symbols, LazyVim's path,
-- lualine's escaped branch) keeps its highlights and alignment, and only the items that run something become text.
-- Anything else (a git tag, a folder name, a debug configuration's name, a typed command) is escaped whole. Applying
-- it twice changes nothing.
function M.sanitize(text)
  if type(text) ~= "string" or not text:find("%", 1, true) then
    return text
  end

  return is_code(text) and defuse(text) or M.escape(text)
end

local KINDS = { "sections", "inactive_sections", "winbar", "inactive_winbar", "tabline" }

local function guard(component)
  local kind = type(component)

  if kind == "string" or kind == "function" then
    return { component, fmt = M.sanitize }
  end

  if kind == "table" and component[1] ~= nil and not guarded[component] then
    local fmt = component.fmt

    component.fmt = fmt and function(text, ctx)
      return M.sanitize(fmt(text, ctx))
    end or M.sanitize

    guarded[component] = true
  end

  return component
end

local function guard_sections(sections)
  for _, kind in ipairs(KINDS) do
    for _, section in pairs(type(sections[kind]) == "table" and sections[kind] or {}) do
      if type(section) == "table" then
        for i, component in ipairs(section) do
          section[i] = guard(component)
        end
      end
    end
  end
end

-- lualine puts a component's text into 'statusline' and escapes only some of its own (branch, filename): every
-- component of opts and of its extensions (neo-tree's shows the working directory, fzf's a file) goes through
-- M.sanitize after its own fmt.
function M.sanitize_components(opts)
  guard_sections(opts)

  local extensions = type(opts.extensions) == "table" and opts.extensions or {}

  for i, extension in ipairs(extensions) do
    if type(extension) == "string" then
      local ok, loaded = pcall(require, "lualine.extensions." .. extension)

      extension = ok and type(loaded) == "table" and vim.deepcopy(loaded) or extension
    end

    if type(extension) == "table" then
      guard_sections(extension)
      extensions[i] = extension
    end
  end
end

-- lualine's branch reads a terminal's directory from its buffer name, term://<cwd>//<pid>:<cmd>, through expand(),
-- which on Linux and macOS runs a `command` in it through the shell, and a repository's folder name can hold one.
-- lualine's own lookup still runs, since only it keeps the branch shown in step with the buffer, but its expand()
-- takes that directory as it is for the call.
function M.guard_git_branch()
  local ok, git_branch = pcall(require, "lualine.components.branch.git_branch")

  if not ok or guarded[git_branch] then
    return
  end

  guarded[git_branch] = true

  local find_git_dir = git_branch.find_git_dir

  ---@diagnostic disable-next-line: duplicate-set-field
  git_branch.find_git_dir = function(dir_path)
    if dir_path ~= nil or not vim.api.nvim_buf_get_name(0):find("^term://") then
      return find_git_dir(dir_path)
    end

    local expand = vim.fn.expand

    -- The buffer's own directory (%:p:h) runs nothing; any other text is the directory from the name.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.expand = function(text, ...)
      if text == "%:p:h" then
        return expand(text, ...)
      end

      return vim.fs.normalize(text, { expand_env = false })
    end

    local done, result = pcall(find_git_dir, nil)

    vim.fn.expand = expand

    if not done then
      error(result, 0)
    end

    return result
  end
end

-- bufferline puts the folder of a duplicate file name in front of it unescaped (it escapes the name itself).
function M.guard_bufferline()
  local ok, duplicates = pcall(require, "bufferline.duplicates")

  if not ok or guarded[duplicates] then
    return
  end

  guarded[duplicates] = true

  local component = duplicates.component

  ---@diagnostic disable-next-line: duplicate-set-field
  duplicates.component = function(context)
    local segment = component(context)

    if type(segment) == "table" and type(segment.text) == "string" then
      segment.text = M.escape(segment.text)
    end

    return segment
  end
end

-- snacks' picker input shows the search in its statuscolumn, and its escape (gsub("%%", "%%")) leaves every % as it
-- is; the items that run something become text.
function M.guard_snacks_input()
  local ok, input = pcall(require, "snacks.picker.core.input")

  if not ok or guarded[input] then
    return
  end

  guarded[input] = true

  local statuscolumn = input.statuscolumn

  input.statuscolumn = function(self)
    local code = statuscolumn(self)

    return type(code) == "string" and defuse(code) or code
  end
end

-- Adds the tag to lualine's section b; nothing where git is not installed.
function M.add_git_tag(opts)
  if vim.fn.executable("git") ~= 1 then
    return
  end

  local section = opts.sections and opts.sections.lualine_b

  if not section then
    return
  end

  watch()
  table.insert(section, math.min(2, #section + 1), {
    git_tag,
    color = tag_color,
    padding = { left = 1, right = 1 },
  })
end

return M
