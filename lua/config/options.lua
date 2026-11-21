local opt = vim.opt

opt.number = true
opt.relativenumber = false
opt.modeline = false
opt.whichwrap:append("h,l,<,>,[,]")
opt.tags = "./tags;"
opt.swapfile = false
opt.spelllang = { "en", "cjk" }
-- UTF-8 and LF for a new file on every system (Windows' default is CRLF); a file read keeps its encoding and line
-- ends, and a project .editorconfig wins. Only a new file that Windows programs alone read gets CRLF: cmd.exe misreads
-- labels and GOTO in an LF batch file, and Windows' own tools (regedit, PowerShell's editors, Visual Studio) write CRLF.
opt.fileformats = { "unix", "dos" }

-- Formats that only Windows programs read, on every system.
local crlf_files = {
  -- cmd.exe
  "*.bat",
  -- regedit, Setup, Windows Script Host
  "*.reg",
  "*.inf",
  "*.vbs",
  "*.wsf",
  -- Visual C++ projects
  "*.vcxproj",
  "*.vcxproj.filters",
  "*.vcxitems",
}

-- On Windows also these, which other systems read with programs of their own, as LF: a .cmd is U-Boot's boot script
-- there, an .rc Android's init file, PowerShell 7 runs .ps1 scripts, the .NET SDK builds solutions, .props and
-- .targets, and cpptools reads .natvis views.
if vim.fn.has("win32") == 1 then
  vim.list_extend(crlf_files, {
    "*.cmd",
    "*.rc",
    "*.ps1",
    "*.psm1",
    "*.psd1",
    "*.sln",
    "*.slnx",
    "*.props",
    "*.targets",
    "*.natvis",
  })
end

-- On Windows a new PowerShell file is UTF-8 with a byte order mark: Windows PowerShell 5.1 reads a script without one
-- in the system's ANSI code page (Windows-1252 or CP949, by the language for non-Unicode programs), which garbles
-- UTF-8's non-ASCII text. A batch file gets none, since cmd.exe would take it for part of the first command.
local POWERSHELL = { ps1 = true, psm1 = true, psd1 = true }

vim.api.nvim_create_autocmd("BufNewFile", {
  group = vim.api.nvim_create_augroup("crlf_windows_files", { clear = true }),
  pattern = crlf_files,
  callback = function(args)
    vim.bo[args.buf].fileformat = "dos"

    if POWERSHELL[vim.fn.fnamemodify(args.file, ":e"):lower()] then
      vim.bo[args.buf].fileencoding = "utf-8"
      vim.bo[args.buf].bomb = true
    end
  end,
  desc = "A new file that only Windows programs read is written with CRLF, a PowerShell one in UTF-8 with a BOM",
})

vim.o.guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor"

-- No plugin here is a remote plugin, so these provider hosts would never be used.
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

-- Neovim types a backup (a.c.orig, a.c~) by the suffix it strips, but clangd picks the language from the last
-- suffix, finds none, and answers every request with "invalid AST". A C-family backup stays plain text.
local c_family = {}

for _, ft in ipairs(require("features.lang.c").C_FAMILY) do
  c_family[ft] = true
end

local function backup_filetype(strip)
  return function(path, bufnr)
    local root = strip(path)

    if root == path or root == "" then
      return
    end

    local ft, on_detect = vim.filetype.match({ buf = bufnr, filename = root })

    if c_family[ft] then
      return "text"
    end

    return ft, on_detect
  end
end

local backup_extension = {}

for _, ext in ipairs({
  "bak",
  "dpkg-bak",
  "dpkg-dist",
  "dpkg-old",
  "dpkg-new",
  "in",
  "new",
  "old",
  "orig",
  "pacsave",
  "pacnew",
  "rpmsave",
  "rpmnew",
}) do
  backup_extension[ext] = backup_filetype(function(path)
    return vim.fn.fnamemodify(path, ":r")
  end)
end

vim.filetype.add({
  extension = vim.tbl_extend("error", backup_extension, {
    S = "asm",
    s = "asm",
    sx = "asm",
    lds = "ld",
  }),
  pattern = {
    [".*%.lds%.S"] = "ld",
    [".*~"] = {
      backup_filetype(function(path)
        return (path:gsub("~+$", "", 1))
      end),
      { priority = 1 },
    },
  },
})
