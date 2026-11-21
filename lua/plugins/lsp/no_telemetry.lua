-- Language servers that send data off the machine by default, told not to. docker-language-server sends telemetry (the
-- client's name, crash traces, hashes of the git remote and of the paths of edited files) to Docker and BugSnag, and
-- looks up every FROM image, a private registry's name included, at Docker Scout. Through vim.lsp.config, so which
-- servers start stays LazyVim's and mason-lspconfig's to decide.
return {
  "neovim/nvim-lspconfig",
  opts = function()
    vim.lsp.config("docker_language_server", {
      init_options = { telemetry = "off" },
      settings = {
        docker = { lsp = { telemetry = "off", experimental = { vulnerabilityScanning = false } } },
      },
    })
  end,
}
