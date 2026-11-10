-- The whole configuration, headless in a test container: no Lua error or error notification while sample files open,
-- and every health check runs. Prints PASS, FAIL and INFO lines for inside.sh.
--   STARTUP_FILES=a.c:b.S nvim --headless -i NONE -c 'luafile tests/containers/startup_check.lua'
local lines = {}
local notes = {}

local function say(kind, text)
  lines[#lines + 1] = ("%s [startup] %s"):format(kind, (tostring(text):gsub("%s+", " ")))
end

local wrapped

-- LazyVim and Snacks replace vim.notify as they load; every replacement is wrapped again.
local function watch_notify()
  local current = vim.notify

  if current == wrapped then
    return
  end

  wrapped = function(msg, level, opts)
    notes[#notes + 1] = { level = level or vim.log.levels.INFO, msg = tostring(msg) }

    return current(msg, level, opts)
  end
  vim.notify = wrapped
end

local function settle(ms)
  vim.wait(ms, function()
    return false
  end, 20)
end

-- LazyVim's temporary vim.notify replays through vim.notify for 500 ms: wrapping it would loop forever.
settle(700)
watch_notify()
pcall(vim.api.nvim_exec_autocmds, "UIEnter", {})
pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "VeryLazy" })
settle(1500)
watch_notify()

for _, file in ipairs(vim.split(os.getenv("STARTUP_FILES") or "", ":", { trimempty = true })) do
  local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(file))

  if ok then
    say("PASS", "opens " .. vim.fs.basename(file) .. " (" .. vim.bo.filetype .. ")")
  else
    say("FAIL", "opening " .. vim.fs.basename(file) .. ": " .. tostring(err))
  end

  watch_notify()
  settle(600)
end

settle(2500)

local ok_health, health_err = pcall(function()
  vim.cmd("checkhealth config features.*")
end)
local health = ok_health and vim.api.nvim_buf_get_lines(0, 0, -1, false) or {}
local old_neovim = vim.fn.has("nvim-0.12") == 0
local failed_checks = 0

if not ok_health then
  say("FAIL", ":checkhealth did not run: " .. tostring(health_err))
end

for _, line in ipairs(health) do
  if line:find("Failed to run healthcheck", 1, true) then
    failed_checks = failed_checks + 1
    say("FAIL", "health: " .. line)
  elseif line:find("ERROR", 1, true) then
    if old_neovim and line:find("older than 0.12", 1, true) then
      say("INFO", "health (expected on this Neovim): " .. line)
    else
      say("FAIL", "health: " .. line)
    end
  elseif line:find("WARNING", 1, true) or line:find("not supported", 1, true) then
    say("INFO", "health: " .. line)
  end
end

if ok_health and failed_checks == 0 then
  say("PASS", "every health check ran")
end

local messages = vim.api.nvim_exec2("messages", { output = true }).output
local lua_errors = 0

for line in vim.gsplit(messages, "\n", { plain = true, trimempty = true }) do
  if line:find("E5108", 1, true) or line:find("E5113", 1, true) or line:find("stack traceback", 1, true) then
    lua_errors = lua_errors + 1
    say("FAIL", "message: " .. line)
  end
end

for _, note in ipairs(notes) do
  if note.level >= vim.log.levels.ERROR then
    lua_errors = lua_errors + 1
    say("FAIL", "error notification: " .. note.msg)
  end
end

if lua_errors == 0 and vim.v.errmsg == "" then
  say("PASS", "no Lua error and no error notification")
elseif vim.v.errmsg ~= "" then
  say("FAIL", "v:errmsg: " .. vim.v.errmsg)
end

for _, client in ipairs(vim.lsp.get_clients()) do
  pcall(function()
    client:stop(true)
  end)
end

vim.wait(3000, function()
  return #vim.lsp.get_clients() == 0
end, 50)
pcall(function()
  require("persistence").stop()
end)
io.stdout:write("\n", table.concat(lines, "\n"), "\n")
io.stdout:flush()
vim.cmd("qall!")
