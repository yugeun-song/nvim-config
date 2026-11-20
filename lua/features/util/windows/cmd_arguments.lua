-- Windows: a path cmd.exe would read as its own syntax. nvim-lint starts every linter as `cmd.exe /C <linter> ...
-- <file>`, and a .cmd or .bat (npm's and Java's launchers) always runs through cmd.exe, which splits a command at & and
-- expands %NAME% whatever quoting libuv gives the arguments (it escapes " as \", which cmd.exe does not know): a file
-- under C:\a&b\ would run b. Such a tool is not started for such a file; Neovim says why once per tool and file.
local M = {}

-- What cmd.exe acts on: & and | split, % expands, ^ escapes, < > redirect, " toggles quoting.
local UNSAFE = '[&|%%^<>"]'

local told = {}

function M.unsafe(path)
  return type(path) == "string" and path:find(UNSAFE) ~= nil
end

-- Whether a program runs through cmd.exe: a .cmd or .bat, as exepath() finds it.
function M.through_cmd(command)
  local path = type(command) == "string" and vim.fn.exepath(command) or ""
  local ext = (path:match("%.(%w+)$") or ""):lower()

  return ext == "cmd" or ext == "bat"
end

-- Says once why tool is not run for path; false, for a condition to return.
function M.refuse(tool, path)
  local key = tool .. "\n" .. path

  if not told[key] then
    told[key] = true
    vim.schedule(function()
      vim.notify(
        ("%s is not run for %s: Windows would start it through cmd.exe, which reads & %% ^ in a path as commands"):format(
          tool,
          path
        ),
        vim.log.levels.WARN
      )
    end)
  end

  return false
end

local lint_guarded = false

-- nvim-lint's try_lint(), which starts every linter of the current buffer through cmd.exe here, whoever calls it:
-- nothing for a file whose path cmd.exe would read. Installed once; anything else passes through unchanged.
function M.guard_lint()
  local ok, lint = pcall(require, "lint")

  if lint_guarded or not ok or type(lint.try_lint) ~= "function" then
    return
  end

  lint_guarded = true

  local try_lint = lint.try_lint

  ---@diagnostic disable-next-line: duplicate-set-field
  lint.try_lint = function(...)
    local path = vim.api.nvim_buf_get_name(0)

    if M.unsafe(path) then
      M.refuse("nvim-lint", path)

      return
    end

    return try_lint(...)
  end
end

-- conform's formatters: one that would start through cmd.exe gets the check before its own condition.
function M.guard_formatters(formatters_by_ft, formatters)
  local done = {}

  local function guard(name)
    local ok, builtin = pcall(require, "conform.formatters." .. name)
    local override = formatters[name] or (ok and {} or nil)

    -- A function override, or a name conform knows neither way, is left as it is.
    if done[name] or type(override) ~= "table" then
      return
    end

    done[name] = true

    local condition = override.condition or (ok and type(builtin) == "table" and builtin.condition or nil)

    override.condition = function(self, ctx)
      local command = self.command

      if type(command) == "function" then
        command = command(self, ctx)
      end

      if M.unsafe(ctx.filename) and M.through_cmd(command) then
        return M.refuse(name, ctx.filename)
      end

      return condition == nil or condition(self, ctx)
    end

    formatters[name] = override
  end

  local function walk(list)
    for _, item in ipairs(list) do
      if type(item) == "string" then
        guard(item)
      elseif type(item) == "table" then
        walk(item)
      end
    end
  end

  for _, list in pairs(formatters_by_ft or {}) do
    if type(list) == "table" then
      walk(list)
    end
  end
end

return M
