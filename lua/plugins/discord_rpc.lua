-- Discord RPC (Rich Presence) for Neovim — original, self-contained implementation.
--
-- The IPC wire protocol (length-prefixed JSON frames; opcodes HANDSHAKE/FRAME/
-- CLOSE/PING/PONG; SET_ACTIVITY) is implemented from public protocol docs only:
-- Discord's official RPC documentation, the MIT-licensed `discord-rpc` reference
-- library's protocol notes, and the Userdoccers RPC reference. No third-party
-- plugin source code is copied; opcode values and message shapes are interface facts.
--
-- Provenance of non-code defaults: the default CLIENT_ID below and the "neovim"
-- art-asset key are not code — they are served by the public Discord application of
-- the andweeb/presence.nvim project. Replace CLIENT_ID with your own Discord
-- application id (and supply your own art asset or an external image URL) to be
-- fully independent.

local uv = vim.uv or vim.loop

local CLIENT_ID = "793271441293967371"
local ENABLED_BY_DEFAULT = true
local MAX_FRAME = 1024 * 1024
local ERROR_LIMIT = 5

local config = {
  client_id = CLIENT_ID,
  details = "Editing in Neovim",
  state = nil,
  show_time = true,
  show_filename = false,
  show_workspace = false,
  large_image = "neovim",
  large_text = "Neovim",
  min_interval = 15000,
  reconnect_backoff = 15000,
  poll_interval = 30000,
  connect_timeout = 5000,
  os_enabled = { linux = true, mac = false, windows = false },
}

local S = {
  running = false,
  status = "idle",
  pipe = nil,
  buf = "",
  start_time = nil,
  last_sent = 0,
  last_attempt = 0,
  nonce = 0,
  gen = 0,
  errors = 0,
  flush_timer = nil,
  poll_timer = nil,
  connect_timer = nil,
}

local function current_os()
  if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    return "windows"
  end
  if vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1 then
    return "mac"
  end
  if vim.fn.has("unix") == 1 then
    return "linux"
  end
  return "other"
end

local function le_u32(n)
  local b0 = n % 256
  n = math.floor(n / 256)
  local b1 = n % 256
  n = math.floor(n / 256)
  local b2 = n % 256
  n = math.floor(n / 256)
  local b3 = n % 256
  return string.char(b0, b1, b2, b3)
end

local function rd_u32(s, i)
  local b0, b1, b2, b3 = s:byte(i, i + 3)
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

local function frame(op, json)
  return le_u32(op) .. le_u32(#json) .. json
end

local function next_nonce()
  S.nonce = S.nonce + 1
  return tostring(S.nonce)
end

local function socket_paths()
  if current_os() == "windows" then
    local paths = {}
    for n = 0, 9 do
      paths[#paths + 1] = string.format([[\\?\pipe\discord-ipc-%d]], n)
    end
    return paths
  end
  local base = os.getenv("XDG_RUNTIME_DIR")
    or os.getenv("TMPDIR")
    or os.getenv("TMP")
    or os.getenv("TEMP")
    or "/tmp"
  local templates = {
    "%s/discord-ipc-%d",
    "%s/snap.discord/discord-ipc-%d",
    "%s/app/com.discordapp.Discord/discord-ipc-%d",
  }
  local paths = {}
  for n = 0, 9 do
    for _, t in ipairs(templates) do
      paths[#paths + 1] = string.format(t, base, n)
    end
  end
  return paths
end

local function path_owner_ok(path)
  if current_os() == "windows" then
    return true
  end
  local st = uv.fs_stat(path)
  if not st then
    return true
  end
  return st.uid == uv.getuid()
end

local function write_raw(op, json)
  if S.pipe and not S.pipe:is_closing() then
    pcall(function()
      S.pipe:write(frame(op, json))
    end)
  end
end

local function send(op, tbl)
  local ok, json = pcall(vim.json.encode, tbl)
  if ok then
    write_raw(op, json)
  end
end

local function build_activity()
  local a = { type = 0 }
  if config.details and config.details ~= "" then
    a.details = config.details
  end
  if config.state and config.state ~= "" then
    a.state = config.state
  end
  if config.show_filename then
    local name = vim.fn.expand("%:t")
    if name ~= "" then
      a.state = "Editing " .. name
    end
  end
  if config.show_workspace then
    local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
    if cwd ~= "" then
      a.details = "In " .. cwd
    end
  end
  if config.show_time and S.start_time then
    a.timestamps = { start = S.start_time }
  end
  if config.large_image then
    a.assets = { large_image = config.large_image, large_text = config.large_text }
  end
  return a
end

local function send_activity()
  S.last_sent = uv.now()
  send(1, {
    cmd = "SET_ACTIVITY",
    nonce = next_nonce(),
    args = { pid = vim.fn.getpid(), activity = build_activity() },
  })
  S.errors = 0
end

local function stop_poll()
  if S.poll_timer then
    S.poll_timer:stop()
    S.poll_timer:close()
    S.poll_timer = nil
  end
end

local function teardown()
  S.gen = S.gen + 1
  if S.connect_timer then
    S.connect_timer:stop()
    S.connect_timer:close()
    S.connect_timer = nil
  end
  if S.flush_timer then
    S.flush_timer:stop()
    S.flush_timer:close()
    S.flush_timer = nil
  end
  if S.pipe then
    if not S.pipe:is_closing() then
      S.pipe:close()
    end
    S.pipe = nil
  end
  S.status = "closed"
  S.buf = ""
end

local function handle_frame(op, payload)
  if op == 1 then
    local ok, msg = pcall(vim.json.decode, payload)
    if ok and msg and msg.cmd == "DISPATCH" and msg.evt == "READY" then
      S.status = "ready"
      S.errors = 0
      if S.connect_timer then
        S.connect_timer:stop()
        S.connect_timer:close()
        S.connect_timer = nil
      end
      vim.schedule(send_activity)
    end
  elseif op == 3 then
    write_raw(4, payload)
  elseif op == 2 then
    teardown()
  end
end

local function on_read(err, chunk)
  if err or not chunk then
    teardown()
    return
  end
  S.buf = S.buf .. chunk
  while #S.buf >= 8 do
    local op = rd_u32(S.buf, 1)
    local len = rd_u32(S.buf, 5)
    if op > 4 or len > MAX_FRAME then
      teardown()
      return
    end
    if #S.buf < 8 + len then
      break
    end
    local payload = S.buf:sub(9, 8 + len)
    S.buf = S.buf:sub(9 + len)
    handle_frame(op, payload)
  end
end

local function do_handshake()
  S.pipe:read_start(on_read)
  send(0, { v = 1, client_id = config.client_id })
end

local function try_connect(paths, idx)
  if idx > #paths then
    S.status = "closed"
    return
  end
  if not path_owner_ok(paths[idx]) then
    return try_connect(paths, idx + 1)
  end
  local pipe = uv.new_pipe(false)
  if not pipe then
    S.status = "closed"
    return
  end
  S.pipe = pipe
  local my_gen = S.gen
  pipe:connect(paths[idx], function(cerr)
    if my_gen ~= S.gen or not S.running then
      if not pipe:is_closing() then
        pipe:close()
      end
      return
    end
    if cerr then
      if not pipe:is_closing() then
        pipe:close()
      end
      if S.pipe == pipe then
        S.pipe = nil
      end
      try_connect(paths, idx + 1)
    else
      S.buf = ""
      do_handshake()
    end
  end)
end

local function ensure_connection()
  if not S.running then
    return
  end
  if S.status == "ready" or S.status == "connecting" then
    return
  end
  local now = uv.now()
  if S.last_attempt ~= 0 and now - S.last_attempt < config.reconnect_backoff then
    return
  end
  S.last_attempt = now
  S.status = "connecting"
  if not S.start_time then
    S.start_time = os.time()
  end
  if S.connect_timer then
    S.connect_timer:stop()
    S.connect_timer:close()
    S.connect_timer = nil
  end
  S.connect_timer = uv.new_timer()
  S.connect_timer:start(config.connect_timeout, 0, function()
    if S.connect_timer then
      S.connect_timer:stop()
      S.connect_timer:close()
      S.connect_timer = nil
    end
    if S.status ~= "ready" then
      teardown()
    end
  end)
  try_connect(socket_paths(), 1)
end

local function request_update()
  ensure_connection()
  if S.status ~= "ready" then
    return
  end
  local now = uv.now()
  local since = now - S.last_sent
  if since >= config.min_interval then
    send_activity()
  elseif not S.flush_timer then
    S.flush_timer = uv.new_timer()
    S.flush_timer:start(config.min_interval - since, 0, function()
      if S.flush_timer then
        S.flush_timer:stop()
        S.flush_timer:close()
        S.flush_timer = nil
      end
      vim.schedule(function()
        if S.status == "ready" then
          send_activity()
        end
      end)
    end)
  end
end

local augroup
local stop

local function guarded(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      S.errors = S.errors + 1
      if S.errors >= ERROR_LIMIT then
        vim.schedule(function()
          if stop then
            stop()
          end
          vim.notify(
            "Discord RPC: disabled after repeated errors (" .. tostring(err) .. ")",
            vim.log.levels.WARN
          )
        end)
      end
    end
  end
end

local function start_poll()
  if S.poll_timer then
    return
  end
  S.poll_timer = uv.new_timer()
  S.poll_timer:start(
    config.poll_interval,
    config.poll_interval,
    vim.schedule_wrap(function()
      if S.running and S.status ~= "ready" then
        guarded(ensure_connection)()
      end
    end)
  )
end

local function start()
  if S.running then
    return true
  end
  if not config.os_enabled[current_os()] then
    return false
  end
  S.running = true
  S.status = "idle"
  S.last_attempt = 0
  S.errors = 0
  augroup = vim.api.nvim_create_augroup("DiscordRpc", { clear = true })
  vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
    group = augroup,
    callback = guarded(request_update),
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      pcall(stop_poll)
      pcall(teardown)
    end,
  })
  start_poll()
  vim.schedule(ensure_connection)
  return true
end

stop = function()
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  pcall(stop_poll)
  pcall(teardown)
  S.running = false
  S.status = "idle"
  S.start_time = nil
  S.last_attempt = 0
  S.errors = 0
end

local function toggle()
  if S.running then
    stop()
    vim.notify("Discord RPC: off", vim.log.levels.INFO)
  elseif start() then
    vim.notify("Discord RPC: on", vim.log.levels.INFO)
  else
    vim.notify("Discord RPC: disabled on this OS", vim.log.levels.WARN)
  end
end

return {
  "discord_rpc",
  virtual = true,
  config = function()
    vim.api.nvim_create_user_command("DiscordRpcToggle", toggle, {
      desc = "Toggle Discord RPC status",
    })
    vim.api.nvim_create_user_command("DiscordRpcStatus", function()
      vim.notify("Discord RPC: " .. (S.running and S.status or "off"), vim.log.levels.INFO)
    end, { desc = "Show Discord RPC status" })
    vim.keymap.set("n", "<leader>uD", toggle, { desc = "Discord RPC toggle" })
    if ENABLED_BY_DEFAULT then
      start()
    end
  end,
}
