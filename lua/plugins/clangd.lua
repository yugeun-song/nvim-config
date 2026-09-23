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
        -- Preambles on disk: a kernel preamble is 10-15 MB per open file, and seven
        -- trees open at once filled a 16 GB machine.
        "--pch-storage=disk",
        -- Unindexed trees yield to editing; `kbuildlab tags` warms the index up front.
        "--background-index-priority=background",
        -- Bound the answers that can blow up on kernel-sized symbol sets.
        "--limit-results=200",
        "--limit-references=2000",
        "-j=" .. half_cpus,
      },
    }
    opts.inlay_hints = opts.inlay_hints or {}
    opts.inlay_hints.enabled = false
  end,
}
