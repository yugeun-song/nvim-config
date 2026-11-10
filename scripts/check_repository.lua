local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(arg[0], ":p"))))
local fix = vim.list_contains(arg, "--fix")
local verbose = vim.list_contains(arg, "--verbose")
local failed = false

local function say(name, status, detail)
  io.stdout:write(("%-12s %s\n"):format(name, status))
  if detail and detail ~= "" and (verbose or status:find("^FAIL")) then
    io.stdout:write(detail, "\n")
  end
end

local function run(cmd)
  local ok, obj = pcall(vim.system, cmd, { cwd = root, text = true })

  if not ok then
    return -1, tostring(obj)
  end

  local res = obj:wait()

  return res.code, (res.stdout or "") .. (res.stderr or "")
end

local function tool(name)
  local path = vim.fn.exepath(name)

  if path ~= "" then
    return path
  end

  local mason = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", name)

  for _, candidate in ipairs({ mason, mason .. ".cmd", mason .. ".exe" }) do
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end
end

local function tracked(pattern)
  local code, out = run({ "git", "ls-files", "-z", "--", pattern })

  if code == 0 then
    return vim.split(out, "\0", { trimempty = true })
  end

  local found = {}

  for path, kind in
    vim.fs.dir(root, {
      depth = math.huge,
      skip = function(dir)
        return dir ~= ".git"
      end,
    })
  do
    if kind == "file" and vim.glob.to_lpeg(pattern):match(vim.fs.basename(path)) then
      found[#found + 1] = path
    end
  end

  return found
end

local function step(name, bin, cmd)
  local exe = tool(bin)

  if not exe then
    say(name, "skip (" .. bin .. " not found)")

    return
  end

  cmd[1] = exe
  local code, out = run(cmd)

  if code == 0 then
    say(name, fix and "fixed" or "ok", out)
  else
    failed = true
    say(name, "FAIL", out)
  end
end

local function blank_rows(src)
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, "lua")

  if not ok then
    return nil
  end

  local tree_root = parser:parse()[1]:root()

  if tree_root:has_error() then
    return nil
  end

  local lines = vim.split(src, "\n", { plain = true })
  local rows = {}

  local function lead_row(row)
    while row > 0 and lines[row]:find("^%s*%-%-") do
      row = row - 1
    end

    return row
  end

  local function has_blank(from, to)
    for row = from, to do
      if lines[row + 1]:find("^%s*$") then
        return true
      end
    end

    return false
  end

  local function visit(node)
    local prev

    for child in node:iter_children() do
      local kind = child:named() and child:type()

      if kind and kind ~= "comment" then
        if prev then
          local p_start, _, p_end = prev:range()
          local start = child:range()
          local need = p_end > p_start
            or kind == "return_statement"
            or (prev:type() == "variable_declaration" and kind ~= "variable_declaration")

          local first = lead_row(start)

          if need and first > p_end and not has_blank(p_end + 1, first - 1) then
            rows[#rows + 1] = first
          end
        end

        prev = child
      end
    end
  end

  local function walk(node)
    for child in node:iter_children() do
      if child:type() == "block" then
        visit(child)
      end

      walk(child)
    end
  end

  visit(tree_root)
  walk(tree_root)
  table.sort(rows)

  return rows, lines
end

local function blank_lines()
  local missing, unparsed, report = 0, 0, {}

  for _, file in ipairs(tracked("*.lua")) do
    local path = vim.fs.joinpath(root, file)
    local fd = assert(io.open(path, "rb"))
    local src = fd:read("*a")

    fd:close()
    local rows, lines = blank_rows(src)

    if not (rows and lines) then
      unparsed = unparsed + 1
      report[#report + 1] = file .. ": not parsed (a syntax error)"
    elseif #rows > 0 then
      missing = missing + #rows
      if fix then
        local out, j = {}, 1

        for i, line in ipairs(lines) do
          if rows[j] == i - 1 then
            out[#out + 1] = ""
            while rows[j] == i - 1 do
              j = j + 1
            end
          end

          out[#out + 1] = line
        end

        fd = assert(io.open(path, "wb"))
        fd:write(table.concat(out, "\n"))
        fd:close()
      else
        for _, row in ipairs(rows) do
          report[#report + 1] = ("%s:%d"):format(file, row + 1)
        end
      end
    end
  end

  if unparsed > 0 then
    failed = true
    say("blank-lines", ("FAIL (%d not parsed)"):format(unparsed), table.concat(report, "\n"))
  elseif missing == 0 or fix then
    say("blank-lines", missing == 0 and "ok" or ("fixed " .. missing), table.concat(report, "\n"))
  else
    failed = true
    say("blank-lines", ("FAIL (%d missing)"):format(missing), table.concat(report, "\n"))
  end
end

local function luals()
  local exe = tool("lua-language-server")

  if not exe then
    say("lua_ls", "skip (lua-language-server not found)")

    return
  end

  local library = { vim.fs.joinpath(vim.env.VIMRUNTIME, "lua"), "${3rd}/luv/library" }
  local lazy = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")

  for name in vim.fs.dir(lazy) do
    local dir = vim.fs.joinpath(lazy, name, "lua")

    if vim.uv.fs_stat(dir) then
      library[#library + 1] = dir
    end
  end

  -- The long form of the path: lua-language-server writes its builtin definitions under --metapath and does not
  -- recognise them as its library when the path is an 8.3 short name (C:/Users/NETRUN~1/...), and then reports
  -- every builtin as undefined.
  local tmp = vim.fn.tempname()

  vim.fn.mkdir(tmp, "p")
  tmp = vim.uv.fs_realpath(tmp) or tmp

  local config = vim.fs.joinpath(tmp, "config.json")
  local result = vim.fs.joinpath(tmp, "check.json")

  vim.fn.writefile({
    vim.json.encode({
      ["runtime.version"] = "LuaJIT",
      ["workspace.library"] = library,
      ["workspace.checkThirdParty"] = false,
      ["diagnostics.globals"] = { "vim", "Snacks", "LazyVim" },
    }),
  }, config)

  run({
    exe,
    "--check=" .. root,
    "--checklevel=Warning",
    "--configpath=" .. config,
    "--logpath=" .. vim.fs.joinpath(tmp, "log"),
    "--metapath=" .. vim.fs.joinpath(tmp, "meta"),
    "--check_format=json",
    "--check_out_path=" .. result,
  })

  local ok, decoded = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(result), "\n"))
  end)

  if not ok or type(decoded) ~= "table" then
    failed = true
    say("lua_ls", "FAIL (no result)")

    return
  end

  local found = {}

  for uri, items in pairs(decoded) do
    local file = vim.fs.relpath(root, vim.uri_to_fname(uri)) or uri

    for _, item in ipairs(items) do
      found[#found + 1] = ("%s:%d [%s] %s"):format(file, item.range.start.line + 1, item.code, item.message)
    end
  end

  table.sort(found)
  if #found == 0 then
    say("lua_ls", "ok")
  else
    failed = true
    say("lua_ls", ("FAIL (%d)"):format(#found), table.concat(found, "\n"))
  end
end

blank_lines()
step("stylua", "stylua", fix and { "stylua", "." } or { "stylua", "--check", "." })
luals()

local toml = tracked("*.toml")

if #toml > 0 then
  step("taplo", "taplo", vim.list_extend(fix and { "taplo", "fmt" } or { "taplo", "fmt", "--check" }, toml))
end

step("rumdl", "rumdl", fix and { "rumdl", "fmt", "." } or { "rumdl", "check", "." })

-- C (native/windows_ime_helper.c and its tests): native/.clang-format, Microsoft-based.
local c_files = tracked("*.c")

if #c_files > 0 then
  local style = "--style=file:" .. vim.fs.joinpath(root, "native", ".clang-format")

  step(
    "clang-format",
    "clang-format",
    vim.list_extend(
      fix and { "clang-format", "-i", style } or { "clang-format", "--dry-run", "--Werror", style },
      c_files
    )
  )
end

local credits = vim.fs.joinpath(root, "scripts", "update_credits.lua")

-- Part of the repository: missing means a rename left this behind, which must fail rather than skip.
if not vim.uv.fs_stat(credits) then
  failed = true
  say("credits", "FAIL", credits .. " is missing")
else
  local code, out = run({ vim.v.progpath, "-l", credits, fix and "--write" or "--check" })

  if code == 0 and out:find("^skipped: ") then
    say("credits", "skip (" .. vim.trim(out:sub(#"skipped: " + 1)) .. ")")
  elseif code == 0 then
    say("credits", fix and "written" or "ok", out)
  else
    failed = true
    say("credits", "FAIL", out)
  end
end

if failed then
  vim.cmd.cquit(1)
end
