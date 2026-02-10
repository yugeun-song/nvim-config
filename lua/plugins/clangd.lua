local cpu_count = #vim.uv.cpu_info()
local half_cpus = math.max(1, math.floor(cpu_count / 2))

return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      clangd = {
        cmd = {
          "clangd",
          "--background-index",
          "--clang-tidy",
          "--completion-style=detailed",
          "--header-insertion=never",
          "-j=" .. half_cpus,
        },
      },
    },
  },
}
