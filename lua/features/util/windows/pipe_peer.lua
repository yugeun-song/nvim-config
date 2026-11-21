-- Windows: whether the server of a named pipe is a process of this user. \\.\pipe\ is one namespace for the whole
-- machine, so another account can create a name first (a Neovim's that has gone, Discord's while Discord is not
-- running); a client that connects then talks to it, and with libuv's default security quality of service the server
-- can act as that client. The pipe is opened here only to be identified (SECURITY_IDENTIFICATION), its server's
-- process id and user compared, and closed; a caller connects for real only to one that passes.
local M = {}

local ffi = require("ffi")

local GENERIC_READ_WRITE = 0xC0000000
local OPEN_EXISTING = 3
local SECURITY_SQOS_PRESENT = 0x00100000
local SECURITY_IDENTIFICATION = 0x00010000
local PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
local TOKEN_QUERY = 0x0008
local TOKEN_USER = 1
local CP_UTF8 = 65001

local declared = false
local advapi32

-- One declaration at a time: another plugin may have declared one of them already.
local function declare()
  if declared then
    return
  end

  declared = true

  for _, declaration in ipairs({
    "void *CreateFileW(const uint16_t *, uint32_t, uint32_t, void *, uint32_t, uint32_t, void *);",
    "int CloseHandle(void *);",
    "int GetNamedPipeServerProcessId(void *, uint32_t *);",
    "void *OpenProcess(uint32_t, int, uint32_t);",
    "void *GetCurrentProcess(void);",
    "int OpenProcessToken(void *, uint32_t, void **);",
    "int GetTokenInformation(void *, int, void *, uint32_t, uint32_t *);",
    "uint32_t GetLengthSid(void *);",
    "int MultiByteToWideChar(uint32_t, uint32_t, const char *, int, uint16_t *, int);",
  }) do
    pcall(ffi.cdef, declaration)
  end

  -- A KnownDLL: always System32's.
  advapi32 = ffi.load("advapi32")
end

local function wide(text)
  local n = ffi.C.MultiByteToWideChar(CP_UTF8, 0, text, #text, nil, 0)
  local buffer = ffi.new("uint16_t[?]", n + 1)

  ffi.C.MultiByteToWideChar(CP_UTF8, 0, text, #text, buffer, n)
  buffer[n] = 0

  return buffer
end

-- The user a process runs as, as the bytes of its SID; nil when it cannot be read.
local function user_of(process)
  local token = ffi.new("void *[1]")

  if advapi32.OpenProcessToken(process, TOKEN_QUERY, token) == 0 then
    return nil
  end

  local size = ffi.new("uint32_t[1]")

  advapi32.GetTokenInformation(token[0], TOKEN_USER, nil, 0, size)

  local info = ffi.new("uint8_t[?]", math.max(size[0], 1))
  local ok = advapi32.GetTokenInformation(token[0], TOKEN_USER, info, size[0], size) ~= 0

  ffi.C.CloseHandle(token[0])

  if not ok then
    return nil
  end

  local sid = ffi.cast("void **", info)[0]

  return ffi.string(sid, advapi32.GetLengthSid(sid))
end

local function is_invalid(handle)
  return handle == nil or ffi.cast("intptr_t", handle) == -1
end

-- Whether path's server runs as this user, and is process pid when one is given.
---@param path string \\.\pipe\name or \\?\pipe\name
---@param pid? integer
function M.served_by_me(path, pid)
  -- jit.os, not has(): this may run in a libuv callback.
  if jit.os ~= "Windows" or type(path) ~= "string" then
    return false
  end

  local ok, result = pcall(function()
    declare()

    local pipe = ffi.C.CreateFileW(
      wide(path),
      GENERIC_READ_WRITE,
      0,
      nil,
      OPEN_EXISTING,
      SECURITY_SQOS_PRESENT + SECURITY_IDENTIFICATION,
      nil
    )

    if is_invalid(pipe) then
      return false
    end

    local server = ffi.new("uint32_t[1]")
    local known = ffi.C.GetNamedPipeServerProcessId(pipe, server) ~= 0

    ffi.C.CloseHandle(pipe)

    if not known or (pid and server[0] ~= pid) then
      return false
    end

    local process = ffi.C.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, server[0])

    if is_invalid(process) then
      return false
    end

    local theirs = user_of(process)

    ffi.C.CloseHandle(process)

    return theirs ~= nil and theirs == user_of(ffi.C.GetCurrentProcess())
  end)

  return ok and result == true
end

return M
