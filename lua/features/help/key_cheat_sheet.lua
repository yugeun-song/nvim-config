-- Every key that does something here, in one searchable list: the mappings of this configuration, its plugins and
-- Neovim's own defaults (all modes, this buffer's included), and Neovim's built-in commands as its :help index
-- documents them. A mapping shows where it was made; a built-in a mapping replaces is marked so.
local M = {}

local INDEX = vim.fs.joinpath(vim.env.VIMRUNTIME, "doc", "index.txt")

-- The mode of each part of index.txt, by the help tag that heads it.
local MODE_OF_SECTION = {
  ["insert-index"] = "i",
  ["normal-index"] = "n",
  ["objects"] = "o",
  ["CTRL-W"] = "n",
  ["["] = "n",
  ["g"] = "n",
  ["z"] = "n",
  ["operator-pending-index"] = "o",
  ["visual-index"] = "x",
  ["ex-edit-index"] = "c",
  ["terminal-mode-index"] = "t",
}

-- The modes :map distinguishes (:help map-modes); "v" is x and s together, so it is not asked for separately.
local MAP_MODES = { "n", "x", "s", "o", "i", "c", "t" }

local built_ins -- parsed once per session

local function parse_index()
  if built_ins then
    return built_ins
  end

  built_ins = {}

  local ok, lines = pcall(vim.fn.readfile, INDEX)

  if not ok then
    return built_ins
  end

  local mode
  local last

  for number, line in ipairs(lines) do
    local section_tag = line:match("^%d[%d.]* .-%*([^*]+)%*")

    if section_tag then
      mode = MODE_OF_SECTION[section_tag]
      last = nil
    elseif line:match("^%d+%. ") then
      mode, last = nil, nil
    elseif mode then
      local tag, rest = line:match("^|([^|]+)|\t+(.*)$")

      if tag then
        local key, description = rest:match("^([^\t]+)\t+(.*)$")

        -- In Neovim's key notation, as mappings are shown: "CTRL-W v" is <C-W>v.
        key = vim.trim(key or rest):gsub("CTRL%-(%S)", "<C-%1>"):gsub("%s+", "")
        description = (description or ""):gsub("^%s*%d?%s*", "")
        last = { mode = mode, lhs = key, desc = description, tag = tag, line = number }
        built_ins[#built_ins + 1] = last
      elseif last and line:match("^\t\t\t") then
        last.desc = last.desc == "" and vim.trim(line) or (last.desc .. " " .. vim.trim(line))
      else
        last = nil
      end
    end
  end

  return built_ins
end

local roots

local function source_of(file)
  if not file or file == "" then
    return "?"
  end

  roots = roots
    or {
      config = vim.fs.normalize(vim.fn.stdpath("config")),
      lazy = vim.fs.normalize(require("lazy.core.config").options.root),
      runtime = vim.fs.normalize(vim.env.VIMRUNTIME),
    }

  -- Neovim's own Lua (vim/_defaults.lua and the like) is named relative to its runtime.
  if file:match("^vim/") then
    return "Neovim"
  end

  local path = vim.fs.normalize(file)
  local lower = vim.fn.has("win32") == 1 and string.lower or function(s)
    return s
  end

  if vim.startswith(lower(path), lower(roots.config) .. "/") then
    return "config"
  elseif vim.startswith(lower(path), lower(roots.lazy) .. "/") then
    return path:sub(#roots.lazy + 2):match("^[^/]+") or "plugin"
  elseif vim.startswith(lower(path), lower(roots.runtime) .. "/") then
    return "Neovim"
  end

  return vim.fn.fnamemodify(path, ":t")
end

-- Where a mapping was made: its Lua callback's definition, else the script and line Neovim recorded.
local function origin(map)
  if map.callback then
    local info = debug.getinfo(map.callback, "S")
    local file = info and info.source and info.source:sub(1, 1) == "@" and info.source:sub(2) or nil

    return file, info and info.linedefined or nil
  end

  if map.sid and map.sid > 0 then
    local script = vim.fn.getscriptinfo({ sid = map.sid })[1]

    return script and script.name or nil, map.lnum
  end
end

local function key_of(mode, lhs)
  return mode .. " " .. vim.fn.keytrans(vim.keycode(lhs))
end

-- lazy.nvim stands in for a plugin not loaded yet with a mapping of its own; the plugin it loads is the real owner.
local function lazy_key_owners()
  local owners = {}

  for name, plugin in pairs(require("lazy.core.config").plugins) do
    for _, key in pairs((plugin._.handlers or {}).keys or {}) do
      for _, mode in ipairs(type(key.mode) == "table" and key.mode or { key.mode or "n" }) do
        owners[key_of(mode, key.lhs)] = name
      end
    end
  end

  return owners
end

local function collect(buf)
  local items, mapped = {}, {}
  local owners = lazy_key_owners()

  local function add_map(map, scope)
    local mode = map.mode == " " and "n" or map.mode

    for i = 1, #mode do
      local m = mode:sub(i, i)
      local id = key_of(m, map.lhs) .. scope

      if not mapped[id] then
        mapped[id] = true
        mapped[key_of(m, map.lhs)] = true

        local file, line = origin(map)
        local desc = map.desc or (map.rhs ~= "" and map.rhs) or (map.callback and "Lua function") or ""
        local source = source_of(file)

        -- A string mapping made from Lua has no recorded origin (sid -8); Neovim's own say :help ...-default.
        if source == "?" then
          source = (map.desc or ""):match("%-default$") and "Neovim" or "Lua, origin not recorded"
        end

        if source == "lazy.nvim" and owners[key_of(m, map.lhs)] then
          source, file, line = owners[key_of(m, map.lhs)] .. " (loads on use)", nil, nil
        end

        items[#items + 1] = {
          kind = "mapping",
          mode = m,
          lhs = vim.fn.keytrans(vim.keycode(map.lhs)),
          desc = desc,
          source = source .. scope,
          file = file and vim.uv.fs_stat(file) and file or nil,
          pos = line and line > 0 and { line, 0 } or nil,
        }
      end
    end
  end

  for _, mode in ipairs(MAP_MODES) do
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      add_map(map, " (this buffer)")
    end

    for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
      add_map(map, "")
    end
  end

  for _, key in ipairs(parse_index()) do
    local replaced = mapped[key_of(key.mode == "x" and "x" or key.mode, key.lhs)]

    items[#items + 1] = {
      kind = "built-in",
      mode = key.mode,
      lhs = key.lhs,
      desc = key.desc,
      source = replaced and "built-in, mapped over" or "built-in",
      tag = key.tag,
      file = INDEX,
      pos = { key.line, 0 },
    }
  end

  for _, item in ipairs(items) do
    item.text = table.concat({ item.mode, item.lhs, item.desc, item.source, item.tag or "" }, " ")
  end

  table.sort(items, function(a, b)
    if a.mode ~= b.mode then
      return a.mode < b.mode
    end

    return a.lhs < b.lhs
  end)

  return items
end

function M.open()
  local items = collect(vim.api.nvim_get_current_buf())

  Snacks.picker({
    title = ("Keys (%d)"):format(#items),
    items = items,
    preview = "file",
    format = function(item)
      return {
        { ("%-2s"):format(item.mode), "Type" },
        { ("%-22s"):format(item.lhs), item.kind == "mapping" and "Special" or "Identifier" },
        { item.desc .. "  " },
        { item.source, "Comment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()

      if not item then
        return
      end

      if item.kind == "built-in" then
        vim.cmd.help(item.tag)
      elseif item.file then
        vim.cmd.edit(vim.fn.fnameescape(item.file))
        if item.pos then
          pcall(vim.api.nvim_win_set_cursor, 0, { item.pos[1], 0 })
        end
      end
    end,
  })
end

M._collect = collect

return M
