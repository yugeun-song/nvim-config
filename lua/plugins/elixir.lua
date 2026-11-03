-- Expert's Erlang nodes listen on every interface with the public cookie "expert": anyone reaching a port runs code.
-- A per-session cookie closes that; ERL_FLAGS keeps the manager on loopback (Expert drops it for the engine).
local cookie = vim.uv.random(24):gsub(".", function(c)
  return ("%02x"):format(c:byte())
end)

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "elixir", "heex", "eex" } },
  },
  {
    -- expert is the language server; elixir-ls stays installed only for its debug adapter.
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        elixirls = { enabled = false },
        expert = {
          cmd_env = {
            RELEASE_COOKIE = cookie,
            ERL_FLAGS = "-kernel inet_dist_use_interface {127,0,0,1}",
          },
        },
      },
    },
  },
}
