-- Common Lisp REPL: sbcl in a terminal split, with no socket anywhere.
local M = {}

local state = {}

-- The pty is line-buffered: the kernel cuts a line at 4095 bytes and acts on ^C, ^U and DEL inside it.
-- Code therefore goes through a file in Neovim's private temp dir; only the short call crosses the pty.
local init = {
  "(defpackage #:nvim-repl (:use #:cl) (:export #:ev))",
  table.concat({
    "(defun nvim-repl:ev (path)",
    "  (let ((result '()))",
    "    (unwind-protect",
    "         (with-open-file (s path)",
    "           (loop for form = (read s nil s) until (eq form s)",
    "                 do (setf result (multiple-value-list (eval form)))))",
    "      (delete-file path))",
    "    (values-list result)))",
  }, "\n"),
  -- ocicl's runtime would otherwise fetch a missing system, unverified, on load.
  '(let ((p (find-package "OCICL-RUNTIME"))) (when p (setf (symbol-value (find-symbol "*DOWNLOAD*" p)) nil)))',
}

local function running()
  return state.job ~= nil and vim.fn.jobwait({ state.job }, 0)[1] == -1
end

local function window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == state.buf then
      return win
    end
  end
end

local function split(buf)
  local cur = vim.api.nvim_get_current_win()
  vim.cmd(buf and "botright 12split" or "botright 12new")
  local win = vim.api.nvim_get_current_win()
  if buf then
    vim.api.nvim_win_set_buf(win, buf)
  end
  return win, cur
end

---@return integer? win the REPL window, opened if needed
function M.start()
  if running() then
    local win = window()
    if not win then
      local cur
      win, cur = split(state.buf)
      vim.api.nvim_set_current_win(cur)
    end
    return win
  end
  if vim.fn.executable("sbcl") ~= 1 then
    vim.notify("sbcl is not on PATH", vim.log.levels.ERROR)
    return
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  local root = vim.fs.root(0, function(name)
    return name == "ocicl.csv" or name == ".git" or name:match("%.asd$") ~= nil
  end)
  local cmd = { "sbcl", "--noinform" }
  for _, form in ipairs(init) do
    vim.list_extend(cmd, { "--eval", form })
  end
  local win, cur = split()
  state.buf = vim.api.nvim_get_current_buf()
  state.job = vim.fn.jobstart(cmd, {
    term = true,
    cwd = root,
    on_exit = function()
      state.job = nil
    end,
  })
  vim.bo[state.buf].buflisted = false
  vim.api.nvim_set_current_win(cur)
  return win
end

function M.toggle()
  local win = running() and window()
  if win then
    pcall(vim.api.nvim_win_close, win, false)
  else
    M.start()
  end
end

local function send(text)
  if not text or not text:find("%S") then
    vim.notify("Nothing to evaluate", vim.log.levels.WARN)
    return
  end
  local win = M.start()
  if not win then
    return
  end
  local path = vim.fn.tempname() .. ".lisp"
  vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
  -- A terminal window follows new output only while its cursor is on the last line.
  vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(state.buf), 0 })
  local label = vim.fn.strcharpart((vim.trim(text:match("[^\n]*")):gsub("%c", " ")), 0, 60)
  local quoted = (path:gsub('[\\"]', "\\%0"))
  vim.fn.chansend(state.job, ('(nvim-repl:ev "%s") ; %s\n'):format(quoted, label))
end

function M.eval_toplevel()
  local ok, node = pcall(vim.treesitter.get_node, { ignore_injections = true })
  if ok and node then
    local root = node:tree():root()
    while node:parent() and node:parent():id() ~= root:id() do
      node = node:parent()
    end
    if node:id() ~= root:id() then
      return send(vim.treesitter.get_node_text(node, 0))
    end
  end
  vim.notify("No form under the cursor", vim.log.levels.WARN)
end

function M.eval_selection()
  local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  send(table.concat(lines, "\n"))
end

function M.eval_buffer()
  send(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"))
end

function M.interrupt()
  if running() then
    vim.fn.chansend(state.job, "\3")
  end
end

function M.stop()
  if running() then
    vim.fn.jobstop(state.job)
  end
end

return M
