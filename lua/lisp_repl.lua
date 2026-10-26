-- Lisp REPLs (sbcl, racket) in a terminal split, with no socket anywhere.
local M = {}

local states = {}

local function quote(s)
  return (s:gsub('[\\"]', "\\%0"))
end

-- The pty is line-buffered: the kernel cuts a line at 4095 bytes and acts on ^C, ^U and DEL inside it.
-- Code therefore goes through a file in Neovim's private temp dir; only the short call crosses the pty.
local sbcl_init = {
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

-- `,ld` loads in any namespace; this load handler deletes the temp files it loads.
local racket_init = [[
(let ([load (current-load)] [dir "%s/"])
  (current-load
   (lambda (path name)
     (dynamic-wind
      void
      (lambda () (load path name))
      (lambda ()
        (when (and (not name) (string-prefix? (path->string path) dir))
          (delete-file path)))))))]]

local profiles = {
  lisp = {
    exe = "sbcl",
    ext = ".lisp",
    root = function(name)
      return name == "ocicl.csv" or name == ".git" or name:match("%.asd$") ~= nil
    end,
    cmd = function()
      local cmd = { "sbcl", "--noinform" }
      for _, form in ipairs(sbcl_init) do
        vim.list_extend(cmd, { "--eval", form })
      end
      return cmd
    end,
    eval = function(path, label)
      return ('(nvim-repl:ev "%s") ; %s\n'):format(quote(path), label)
    end,
  },
  racket = {
    exe = "racket",
    ext = ".rkt",
    -- Under TERM=dumb xrepl reads plain lines and saves no history.
    env = { TERM = "dumb" },
    root = function(name)
      return name == "info.rkt" or name == ".git"
    end,
    cmd = function()
      return { "racket", "-e", racket_init:format(quote(vim.fs.dirname(vim.fn.tempname()))), "-i" }
    end,
    eval = function(path)
      return (',ld "%s"\n'):format(quote(path))
    end,
    run = function(file)
      return (',enter (file "%s")\n'):format(quote(file))
    end,
  },
}

local function current()
  local ft = vim.bo.filetype
  states[ft] = states[ft] or {}
  return profiles[ft], states[ft]
end

local function running(state)
  return state.job ~= nil and vim.fn.jobwait({ state.job }, 0)[1] == -1
end

local function window(state)
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
  local profile, state = current()
  if running(state) then
    local win = window(state)
    if not win then
      local cur
      win, cur = split(state.buf)
      vim.api.nvim_set_current_win(cur)
    end
    return win
  end
  if vim.fn.executable(profile.exe) ~= 1 then
    vim.notify(profile.exe .. " is not on PATH", vim.log.levels.ERROR)
    return
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  local root = vim.fs.root(0, profile.root)
  local cmd = profile.cmd()
  local win, cur = split()
  state.buf = vim.api.nvim_get_current_buf()
  state.job = vim.fn.jobstart(cmd, {
    term = true,
    cwd = root,
    env = profile.env,
    on_exit = function()
      state.job = nil
    end,
  })
  vim.bo[state.buf].buflisted = false
  vim.api.nvim_set_current_win(cur)
  return win
end

function M.toggle()
  local _, state = current()
  local win = running(state) and window(state)
  if win then
    pcall(vim.api.nvim_win_close, win, false)
  else
    M.start()
  end
end

local function deliver(win, line)
  local _, state = current()
  -- A terminal window follows new output only while its cursor is on the last line.
  vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(state.buf), 0 })
  vim.fn.chansend(state.job, line)
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
  local profile = current()
  local path = vim.fn.tempname() .. profile.ext
  vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
  local label = vim.fn.strcharpart((vim.trim(text:match("[^\n]*")):gsub("%c", " ")), 0, 60)
  deliver(win, profile.eval(path, label))
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
  local profile = current()
  if not profile.run then
    return send(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"))
  end
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    vim.notify("Write the buffer to a file first", vim.log.levels.WARN)
    return
  end
  vim.cmd("update")
  local win = M.start()
  if win then
    deliver(win, profile.run(vim.fn.fnamemodify(file, ":p")))
  end
end

function M.interrupt()
  local _, state = current()
  if running(state) then
    vim.fn.chansend(state.job, "\3")
  end
end

function M.stop()
  local _, state = current()
  if running(state) then
    vim.fn.jobstop(state.job)
  end
end

return M
