-- Language servers started from Mason's or PATH's program with fixed arguments, never a repository's. nvim-lspconfig
-- starts jsonls, cssls, html, yamlls and oxlint from <root>/node_modules/.bin when a repository ships one, which runs
-- that repository's program on opening a file. jdtls keeps a workspace per project named after the project's folder;
-- on Windows jdtls is a .cmd, and cmd.exe reads & or % in that name as commands, so the name here is the folder's
-- letters and digits with a hash of the whole root.
local function jdtls_cmd(dispatchers, config)
  local name = "default"

  if config.root_dir then
    local folder = vim.fs.basename(config.root_dir):gsub("[^%w._-]", "_")

    name = ("%s-%s"):format(folder, vim.fn.sha256(config.root_dir):sub(1, 12))
  end

  local data = vim.fs.joinpath(vim.fn.stdpath("cache"), "jdtls", "workspace", name)

  if vim.fn.has("win32") == 1 and require("features.util.windows.cmd_arguments").unsafe(data) then
    error(("jdtls is not started: its workspace %s holds a character cmd.exe would read as a command"):format(data))
  end

  local cmd = { "jdtls", "-data", data }

  -- As nvim-lspconfig passes them.
  for arg in (os.getenv("JDTLS_JVM_ARGS") or ""):gmatch("%S+") do
    cmd[#cmd + 1] = "--jvm-arg=" .. arg
  end

  return vim.lsp.rpc.start(cmd, dispatchers, {
    cwd = config.cmd_cwd,
    env = config.cmd_env,
    detached = config.detached,
  })
end

local FIXED = {
  jsonls = { cmd = { "vscode-json-language-server", "--stdio" } },
  cssls = { cmd = { "vscode-css-language-server", "--stdio" } },
  html = { cmd = { "vscode-html-language-server", "--stdio" } },
  yamlls = { cmd = { "yaml-language-server", "--stdio" } },
  oxlint = { cmd = { "oxlint", "--lsp" } },
  jdtls = { cmd = jdtls_cmd },
}

return {
  "neovim/nvim-lspconfig",
  -- Through vim.lsp.config, not opts.servers: which servers start stays LazyVim's and mason-lspconfig's to decide.
  opts = function(_, opts)
    for name, fixed in pairs(FIXED) do
      local server = (opts.servers or {})[name]

      -- A spec's own cmd is kept.
      if not (type(server) == "table" and server.cmd) then
        vim.lsp.config(name, fixed)
      end
    end
  end,
}
