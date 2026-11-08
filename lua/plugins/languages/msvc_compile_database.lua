-- Windows only: compile_commands.json from a Visual Studio project, rebuilt when it falls behind
-- (lua/features/languages/c_and_cpp/msvc_toolchain/compile_database.lua).
if vim.fn.has("win32") == 0 then
  return {}
end

return {
  "msvc_compile_database",
  virtual = true,
  cmd = "MsvcCompileDb",
  ft = { "c", "cpp", "cuda" },
  config = function()
    local db = require("features.languages.c_and_cpp.msvc_toolchain.compile_database")
    local group = vim.api.nvim_create_augroup("msvc_compile_database", { clear = true })

    vim.api.nvim_create_user_command("MsvcCompileDb", function(args)
      db.generate({ configuration = args.fargs[1], platform = args.fargs[2] })
    end, {
      nargs = "*",
      complete = function(_, line)
        local n = #vim.split(vim.trim(line), "%s+")

        return n <= 1 and { "Debug", "Release" } or { "x64", "Win32", "ARM64" }
      end,
      desc = "compile_commands.json from the nearest .sln, .slnx or .vcxproj: MsvcCompileDb [Configuration] [Platform]",
    })

    vim.api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = { "c", "cpp", "cuda" },
      callback = function(ev)
        db.ensure(ev.buf)
      end,
    })

    vim.api.nvim_create_autocmd("BufWritePost", {
      group = group,
      pattern = { "*.sln", "*.slnx", "*.vcxproj", "*.props", "*.targets" },
      callback = db.forget,
    })

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local ft = vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype

      if ft == "c" or ft == "cpp" or ft == "cuda" then
        db.ensure(buf)
      end
    end
  end,
}
