local function private_tmp()
  local base = vim.fs.joinpath(vim.fn.stdpath("cache"), "clangd-tmp")
  for name in vim.fs.dir(base) do
    local pid = tonumber(name)
    if pid and pid ~= vim.fn.getpid() and vim.uv.kill(pid, 0) ~= 0 then
      pcall(vim.fs.rm, vim.fs.joinpath(base, name), { recursive = true, force = true })
    end
  end
  local dir = vim.fs.joinpath(base, tostring(vim.fn.getpid()))
  vim.fn.mkdir(dir, "p", tonumber("700", 8))
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("clangd_tmp", { clear = true }),
    callback = function()
      pcall(vim.fs.rm, dir, { recursive = true, force = true })
    end,
  })
  return dir
end

return {
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    local cpu_info = vim.uv.cpu_info()
    local cpu_count = cpu_info and #cpu_info or 1
    local half_cpus = math.max(1, math.floor(cpu_count / 2))

    local tmp = private_tmp()
    opts.servers = opts.servers or {}
    opts.servers.clangd = {
      cmd = {
        "clangd",
        "--background-index",
        "--clang-tidy",
        "--completion-style=detailed",
        "--header-insertion=never",
        -- Preambles on disk: a kernel preamble is 10-15 MB per open file, and seven
        -- trees open at once filled a 16 GB machine.
        "--pch-storage=disk",
        -- Unindexed trees yield to editing; an index built ahead of time skips the wait.
        "--background-index-priority=background",
        -- Bound the answers that can blow up on kernel-sized symbol sets.
        "--limit-results=200",
        "--limit-references=2000",
        -- Neovim logs server stderr at ERROR; clangd's info lines grew lsp.log past 100 MB.
        "--log=error",
        "-j=" .. half_cpus,
      },
      cmd_env = { TMPDIR = tmp, TMP = tmp, TEMP = tmp },
    }
  end,
}
