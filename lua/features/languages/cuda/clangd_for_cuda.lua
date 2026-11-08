-- clangd for CUDA (.cu, .cuh), on every system. Nothing here runs for C or C++ files.
-- 1. A compile database written for nvcc (CMake's, Bear's) holds nvcc's command line, which clang does not
--    read: unknown options, no toolkit, and then __global__, threadIdx, dim3 and even a correct <<< >>> come
--    back as errors. An open CUDA file whose command is nvcc's gets the clang command that compiles it the same
--    way (include directories, definitions, standard, the first GPU, the toolkit nvcc belongs to), through
--    clangd's compilationDatabaseChanges extension; the database itself is not touched.
-- 2. Two diagnostics clang gives where nvcc compiles: a launch spelled with spaces between its angle brackets
--    (<< < ... >> >, as Visual Studio's formatter writes it; clang only lexes <<< and >>>), and "not used
--    directly" for the headers every CUDA compilation includes by itself (cuda_runtime.h and those it stands
--    for). They are dropped from CUDA files, and only they.
-- 3. A CUDA file without a compile command gets the toolkit as clangd's fallback flags: clang looks for one only
--    in a few fixed places (/usr/local/cuda, beside ptxas on PATH; on Windows only where CUDA 7 and 8 went).
local M = {}

local uv = vim.uv
local WIN = vim.fn.has("win32") == 1

local function is_cuda(path)
  local lower = path:lower()

  return lower:sub(-3) == ".cu" or lower:sub(-4) == ".cuh"
end

local function valid_toolkit(dir)
  return dir and dir ~= "" and uv.fs_stat(vim.fs.joinpath(dir, "include", "cuda_runtime.h")) and vim.fs.normalize(dir)
    or nil
end

-- The toolkit: CUDA_PATH (NVIDIA's installer sets it on Windows, Arch's cuda package in /etc/profile.d), else
-- the one nvcc on PATH belongs to.
function M.toolkit()
  local dir = valid_toolkit(vim.env.CUDA_PATH)

  if dir then
    return dir
  end

  local nvcc = vim.fn.exepath("nvcc")

  if nvcc ~= "" then
    return valid_toolkit(vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(uv.fs_realpath(nvcc) or nvcc))))
  end
end

-- clangd's fallbackFlags, or nil without a toolkit. A C or C++ file ignores them.
function M.fallback_flags()
  local dir = M.toolkit()

  return dir and { "--cuda-path=" .. dir, "-Wno-unknown-cuda-version" } or nil
end

-- Included by every CUDA compilation already (nvcc's implicit cuda_runtime.h, clang's CUDA wrapper header):
-- including them again is the convention, not a mistake.
local IMPLICIT = {
  ["cuda_runtime.h"] = true,
  ["cuda_runtime_api.h"] = true,
  ["cuda.h"] = true,
  ["device_launch_parameters.h"] = true,
}

-- What clang reports on a launch spelled << < ... >> >: the brackets, then its arguments read as a comma
-- expression.
local LAUNCH_NOISE = { expected_expression = true, ["-Wunused-value"] = true }

local function spaced(line)
  return line:find("<<[ \t]+<") or line:find(">>[ \t]+>")
end

-- Whether 1-based row lies in a statement holding a spaced launch: that line, or one after it before the
-- statement ends.
local function in_spaced_launch(lines, row)
  for j = row, math.max(1, row - 20), -1 do
    local line = lines[j]

    if not line or (j < row and line:find(";", 1, true)) then
      return false
    end

    if spaced(line) then
      return true
    end
  end

  return false
end

local function implicit_include(d)
  local header = d.code == "unused-includes" and (d.message or ""):match('^Included header [<"]?([^%s>"]+)')

  return header and IMPLICIT[vim.fs.basename(header):lower()] or false
end

-- publishDiagnostics params for a CUDA document, without the two kinds above.
function M.filter(params)
  if not (params and params.uri and params.diagnostics and is_cuda(params.uri)) then
    return params
  end

  local lines

  params.diagnostics = vim.tbl_filter(function(d)
    if implicit_include(d) then
      return false
    end

    if LAUNCH_NOISE[d.code] and d.range then
      if not lines then
        local fname = vim.uri_to_fname(params.uri)
        local bufnr = vim.fn.bufnr(fname)
        local ok, text = pcall(vim.fn.readfile, fname)

        lines = bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          or (ok and text or {})
      end

      return not in_spaced_launch(lines, d.range.start.line + 1)
    end

    return true
  end, params.diagnostics)

  return params
end

-- A command string as a shell splits it: blanks separate, quotes group; a backslash escapes outside Windows,
-- where it is the path separator.
local function split(cmd)
  local args, cur, quote = {}, nil, nil
  local i, n = 1, #cmd

  while i <= n do
    local c = cmd:sub(i, i)

    if quote then
      if c == quote then
        quote = nil
      elseif c == "\\" and not WIN and quote == '"' and i < n then
        i = i + 1
        cur = cur .. cmd:sub(i, i)
      else
        cur = cur .. c
      end
    elseif c:match("%s") then
      if cur then
        args[#args + 1], cur = cur, nil
      end
    elseif c == '"' or (c == "'" and not WIN) then
      quote, cur = c, cur or ""
    elseif c == "\\" and not WIN and i < n then
      i = i + 1
      cur = (cur or "") .. cmd:sub(i, i)
    else
      cur = (cur or "") .. c
    end

    i = i + 1
  end

  if cur then
    args[#args + 1] = cur
  end

  return args
end

local function is_nvcc(prog)
  local name = vim.fs.basename(vim.fs.normalize(prog or "")):lower():gsub("%.exe$", "")

  return name == "nvcc"
end

-- nvcc options that carry what clang needs, by spelling: their clang form for a value.
local SEPARATE = {
  ["-I"] = "-I",
  ["--include-path"] = "-I",
  ["-D"] = "-D",
  ["--define-macro"] = "-D",
  ["-U"] = "-U",
  ["--undefine-macro"] = "-U",
  ["-isystem"] = "-isystem",
  ["--system-include"] = "-isystem",
  ["-include"] = "-include",
  ["--pre-include"] = "-include",
  ["-std"] = "-std=",
  ["--std"] = "-std=",
}

-- Options whose value names GPUs.
local ARCH = {
  ["-arch"] = true,
  ["--gpu-architecture"] = true,
  ["-gencode"] = true,
  ["--generate-code"] = true,
  ["-code"] = true,
  ["--gpu-code"] = true,
}

local function gpu_of(value)
  local sm = value:match("sm_%d+%a?")
  local virtual = value:match("compute_(%d+%a?)")

  return sm or (virtual and "sm_" .. virtual)
end

-- The clang arguments an nvcc command's own arguments amount to; unknown ones are dropped.
local function translate(args, dir, out, state)
  local i = 1

  local function add(flag, value)
    if flag:sub(-1) == "=" then
      out[#out + 1] = flag .. value
    elseif flag == "-I" or flag == "-D" or flag == "-U" then
      out[#out + 1] = flag .. value
    else
      vim.list_extend(out, { flag, value })
    end
  end

  while i <= #args do
    local a = args[i]
    local name, joined = a:match("^(%-%-?[%w%-]+)=(.*)$")

    name = name or a

    if SEPARATE[a] and args[i + 1] then
      add(SEPARATE[a], args[i + 1])
      i = i + 1
    elseif joined and SEPARATE[name] then
      add(SEPARATE[name], joined)
    elseif a:match("^%-[IDU].") then
      out[#out + 1] = a
    elseif a:match("^%-isystem.") then
      add("-isystem", a:sub(9))
    elseif ARCH[name] then
      local value = joined or args[i + 1] or ""

      state.arch = state.arch or gpu_of(value)
      i = i + (joined and 0 or 1)
    elseif name == "--options-file" or name == "-optf" or a:sub(1, 1) == "@" then
      local file = a:sub(1, 1) == "@" and a:sub(2) or joined or args[i + 1]

      i = i + ((joined or a:sub(1, 1) == "@") and 0 or 1)

      -- A regular file of sensible size, each once, eight deep at most: a response file naming itself, a device
      -- or a pipe would loop or block Neovim.
      if file and (state.depth or 0) < 8 then
        local path = vim.fs.joinpath(dir, file)

        path = uv.fs_stat(path) and path or file

        local st = uv.fs_stat(path)
        local real = uv.fs_realpath(path) or path

        state.seen = state.seen or {}
        if st and st.type == "file" and st.size <= 1048576 and not state.seen[real] then
          state.seen[real] = true

          local ok, text = pcall(vim.fn.readfile, path)

          if ok then
            state.depth = (state.depth or 0) + 1
            translate(split(table.concat(text, " ")), dir, out, state)
            state.depth = state.depth - 1
          end
        end
      end
    elseif name == "-Xcompiler" or name == "--compiler-options" then
      local value = joined or args[i + 1] or ""

      i = i + (joined and 0 or 1)

      -- Host options, comma-separated; keep their definitions and include directories (/D and /I for cl).
      for _, opt in ipairs(vim.split(value, ",", { trimempty = true })) do
        local flag, rest = opt:match("^[/%-]([DUI])(.+)$")

        if flag then
          out[#out + 1] = "-" .. flag .. rest
        end
      end
    end

    i = i + 1
  end
end

local function clang_command(entry)
  local args = entry.arguments or split(entry.command or "")

  if not is_nvcc(args[1]) then
    return nil
  end

  local dir = entry.directory or ""
  local file = entry.file
  local nvcc = args[1]
  local resolved = (nvcc:find("[/\\]") and nvcc) or vim.fn.exepath(nvcc)
  local toolkit = resolved ~= ""
      and valid_toolkit(vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(uv.fs_realpath(resolved) or resolved))))
    or M.toolkit()

  local out, state = { "clang++", "-x", "cuda", "-Wno-unknown-cuda-version" }, {}

  if toolkit then
    out[#out + 1] = "--cuda-path=" .. toolkit
  end

  translate(vim.list_slice(args, 2), dir, out, state)

  if state.arch then
    out[#out + 1] = "--cuda-gpu-arch=" .. state.arch
  end

  out[#out + 1] = file

  return out
end

local function key(path)
  path = vim.fs.normalize(path)

  return WIN and path:lower() or path
end

-- Where clangd looks: compile_commands.json in each directory above the file, or in its build/.
local function database_for(file)
  for dir in vim.fs.parents(file) do
    for _, sub in ipairs({ "", "build" }) do
      local path = vim.fs.joinpath(dir, sub, "compile_commands.json")

      if uv.fs_stat(path) then
        return path
      end
    end
  end
end

-- Read and decoded in a worker thread, which hands back only the CUDA entries: a database of a few hundred MB
-- would otherwise hold the editor for seconds. Most databases hold no CUDA file at all; those are not decoded.
local function read_cuda_entries(db, done)
  local work = uv.new_work(function(path)
    local ok, json = pcall(function()
      local fd = assert(vim.uv.fs_open(path, "r", 438))
      local st = vim.uv.fs_fstat(fd)
      local text = st and vim.uv.fs_read(fd, st.size, 0) or ""

      vim.uv.fs_close(fd)
      if not text:find("nvcc", 1, true) then
        return "[]"
      end

      local entries = {}

      for _, e in ipairs(vim.json.decode(text)) do
        local file = type(e) == "table" and e.file

        if type(file) == "string" and (file:lower():find("%.cu$") or file:lower():find("%.cuh$")) then
          entries[#entries + 1] = e
        end
      end

      return vim.json.encode(entries)
    end)

    return ok and json or "[]"
  end, function(json)
    vim.schedule(function()
      local ok, entries = pcall(vim.json.decode, json)

      done(ok and type(entries) == "table" and entries or {})
    end)
  end)

  work:queue(db)
end

local loaded = {} -- database path -> { stamp, by_file } once read; { stamp, waiting } while being read

-- done(entry): file's entry in db, or nil.
local function entry_for(db, file, done)
  local st = uv.fs_stat(db)
  local stamp = st and ("%d.%d:%d"):format(st.mtime.sec, st.mtime.nsec, st.size)
  local cached = loaded[db]

  local function answer()
    done(cached.by_file[key(file)])
  end

  if cached and cached.stamp == stamp then
    if cached.by_file then
      return answer()
    end

    cached.waiting[#cached.waiting + 1] = answer

    return
  end

  cached = { stamp = stamp, waiting = { answer } }
  loaded[db] = cached
  read_cuda_entries(db, function(entries)
    local by_file = {}

    for _, e in ipairs(entries) do
      local abs = e.file

      if not (abs:match("^/") or abs:match("^%a:[/\\]")) then
        abs = vim.fs.joinpath(type(e.directory) == "string" and e.directory or "", abs)
      end

      by_file[key(abs)] = e
    end

    local waiting = cached.waiting

    cached.by_file, cached.waiting = by_file, nil
    for _, waiter in ipairs(waiting) do
      waiter()
    end
  end)
end

-- On clangd attaching to a CUDA buffer: its nvcc command, if it has one, as clang's.
function M.attach(client, bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)

  if file == "" or not is_cuda(file) then
    return
  end

  local db = database_for(file)

  if not db then
    return
  end

  entry_for(db, file, function(entry)
    local command = entry and clang_command(entry)

    if not command or client:is_stopped() then
      return
    end

    client:notify("workspace/didChangeConfiguration", {
      settings = {
        compilationDatabaseChanges = {
          [file] = { workingDirectory = entry.directory, compilationCommand = command },
        },
      },
    })
  end)
end

M._translate = clang_command

return M
