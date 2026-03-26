return {
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    local cpu_info = vim.uv.cpu_info()
    local cpu_count = cpu_info and #cpu_info or 1
    local half_cpus = math.max(1, math.floor(cpu_count / 2))

    opts.servers = opts.servers or {}
    opts.servers.clangd = {
      cmd = {
        "clangd",
        "--background-index",
        "--clang-tidy",
        "--completion-style=detailed",
        "--header-insertion=never",
        "-j=" .. half_cpus,
      },
    }
    opts.inlay_hints = opts.inlay_hints or {}
    opts.inlay_hints.enabled = false
  end,
}
