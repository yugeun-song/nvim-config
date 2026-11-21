-- Windows: a path cmd.exe would read as its own syntax. nvim-lint starts every linter as `cmd.exe /C <linter> ...
-- <file>`, and a .cmd or .bat (npm's and Java's launchers) always runs through cmd.exe, which splits a command at & and
-- expands %NAME% whatever quoting libuv gives the arguments (it escapes " as \", which cmd.exe does not know): a file
-- under C:\a&b\ would run b. An npm formatter is started as node itself; any other such tool is not started for such
-- a file, and Neovim says why once per tool and file.
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

-- conform's formatters. One whose .cmd only runs node with a script (npm's launcher, behind Mason's) starts node itself,
-- with the script first, so no cmd.exe stands between Neovim and it. One that would still start through cmd.exe is not
-- run for a file whose path cmd.exe would read: the buffer is handed back as it is, and so counts as formatted, or
-- LazyVim would format it through a language server instead.
function M.guard_formatters(formatters_by_ft, formatters)
  local npm = require("features.util.windows.npm_launcher")
  local done = {}

  local function guard(name)
    local ok, builtin = pcall(require, "conform.formatters." .. name)

    builtin = ok and type(builtin) == "table" and builtin or nil

    local override = formatters[name] or (builtin and {} or nil)

    -- A function override, a Lua formatter, or a name conform knows neither way, is left as it is.
    if done[name] or type(override) ~= "table" or override.format then
      return
    end

    done[name] = true

    local command = override.command or (builtin and builtin.command)
    local prepend = override.prepend_args

    if command == nil then
      return
    end

    -- What runs: the command and the arguments before conform's own, node and the script first for an npm program.
    local function plan(self, ctx)
      local cmd = command

      if type(cmd) == "function" then
        cmd = cmd(self, ctx)
      end

      local args = prepend

      if type(args) == "function" then
        args = args(self, ctx)
      end

      local node = type(cmd) == "string" and cmd ~= "" and type(args) ~= "string" and npm.resolve(vim.fn.exepath(cmd))

      if node then
        return node.node, vim.list_extend({ node.script }, args or {})
      end

      return cmd, args or {}
    end

    override.command = function(self, ctx)
      return (plan(self, ctx))
    end

    override.prepend_args = function(self, ctx)
      return select(2, plan(self, ctx))
    end

    local handed_back = {
      inherit = false,
      format = function(_, ctx, lines, callback)
        M.refuse(name, ctx.filename)
        callback(nil, lines)
      end,
    }

    formatters[name] = function(bufnr)
      if M.unsafe(vim.api.nvim_buf_get_name(bufnr)) then
        local config = builtin and require("conform.util").merge_formatter_configs(builtin, override) or override
        local cmd = config.command

        if type(cmd) == "function" then
          cmd = cmd(config, require("conform.runner").build_context(bufnr, config))
        end

        if M.through_cmd(cmd) then
          return handed_back
        end
      end

      return override
    end
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
