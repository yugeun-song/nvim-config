-- Neovim back to a fresh clone of this configuration (lua/features/maintenance/stored_data_paths.lua says what
-- that removes).
--   nvim -l scripts/reset_to_fresh_clone.lua
--       lists where everything is; in a terminal it then asks for "reset" to be typed and removes only on that.
--       Close every Neovim and Neovide first.
-- There is no flag that skips the question, and an answer from a pipe or a file is not taken.
-- :ManagedPathsReset starts it with --after PID[,PID] --token T once "reset" was typed in Neovim: it waits for
-- that Neovim (and its Neovide) to exit, removes only when T is the confirmation that prompt left, and writes
-- the result to stdpath("state")/nvim-config/reset_report.txt for the next start to show.
local script_dir = vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(arg[0], ":p")))

package.path = vim.fs.joinpath(script_dir, "..", "lua", "?.lua") .. ";" .. package.path

local mp = require("features.maintenance.stored_data_paths")

local after, token, scope = {}, nil, "all"

for i = 1, #arg do
  if arg[i] == "--after" and arg[i + 1] then
    for pid in arg[i + 1]:gmatch("%d+") do
      after[#after + 1] = tonumber(pid)
    end
  elseif arg[i] == "--token" then
    token = arg[i + 1]
  elseif arg[i] == "--scope" then
    scope = arg[i + 1] == "configuration" and "configuration" or "all"
  elseif arg[i] == "--yes" then
    print('--yes no longer exists: run it in a terminal and type "reset" when asked.')
  end
end

local function stamp()
  return os.date("%Y-%m-%d %H:%M ")
end

local function report(head, lines)
  local file = mp.report_file()

  vim.fn.mkdir(vim.fs.dirname(file), "p")
  pcall(vim.fn.writefile, vim.list_extend({ head }, lines or {}), file)
end

if #after > 0 then
  local gone = vim.wait(120000, function()
    for _, pid in ipairs(after) do
      if vim.uv.kill(pid, 0) == 0 then
        return false
      end
    end

    return true
  end, 100)

  if not mp.consume_token(token) then
    report(stamp() .. 'not done: no "reset" typed at :ManagedPathsReset came with it')
    os.exit(1)
  end

  if not gone then
    report(stamp() .. "not done: Neovim was still running two minutes later")
    os.exit(1)
  end
else
  local doomed

  if scope == "configuration" then
    doomed = mp.removable(mp.configuration_items())
    print("This configuration's own files:")
    for _, item in ipairs(doomed) do
      print("  " .. mp.display(item.path) .. "  (" .. item.note .. ")")
    end
  else
    local view = mp.view()

    mp.measure(view)
    print(table.concat(mp.render(view, { hint = false }), "\n"))
    doomed = mp.removable(view.items)
  end

  doomed = #doomed

  if doomed == 0 then
    print("\nNothing to remove.")
    os.exit(0)
  end

  if vim.uv.guess_handle(0) ~= "tty" then
    print('\nNothing was removed. Run it in a terminal to be asked; only "reset" typed there removes.')
    os.exit(0)
  end

  io.write(('\nType "reset" to remove the %d "remove" lines (anything else keeps them): '):format(doomed))
  io.flush()

  local answer = (io.read("l") or ""):gsub("\r$", "")

  if answer ~= "reset" then
    print("Nothing was removed.")
    os.exit(0)
  end
end

local others = mp.other_instances(after)

if #others > 0 then
  local head = stamp()
    .. ("not done: close the running Neovim instances first (PID %s)"):format(table.concat(others, ", "))

  if #after > 0 then
    report(head)
  else
    print(head)
  end

  os.exit(1)
end

local head, lines = mp.summary(mp.remove(mp.items_for(scope)))

if #after > 0 then
  report(head, lines)
else
  print(head)
  print(table.concat(lines, "\n"))
end

os.exit(head:find("kept") and 1 or 0)
