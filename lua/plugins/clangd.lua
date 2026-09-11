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
        -- Keep preambles on disk instead of in RAM.  A kernel preamble is
        -- 10-15 MB and clangd holds one per open file; with seven trees open
        -- at once that is most of a 16 GB machine.  They live beside the
        -- compilation database, which is already out of the source tree.
        "--pch-storage=disk",
        -- Index in the background at low priority, so a tree that still has
        -- indexing left to do yields to the editing you opened it for.
        -- `kbuildlab tags` warms the index up front; this covers what is left.
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
