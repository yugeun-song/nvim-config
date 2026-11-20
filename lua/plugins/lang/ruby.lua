-- Ruby: ruby-lsp answers, rubocop lints and formats, rdbg debugs; irb is the REPL (after/ftplugin/ruby.lua).
local MARKERS = { "Gemfile", ".git" }

-- The project root, else the file's folder. Never the home or filesystem root: ruby-lsp indexes the whole workspace
-- and requires every ruby_lsp/**/addon.rb inside it.
local function ruby_root(bufnr, on_dir)
  local name = vim.api.nvim_buf_get_name(bufnr)

  if name == "" then
    return
  end

  local root = vim.fs.root(bufnr, MARKERS) or vim.fs.dirname(name)
  local home = vim.fs.normalize("~")

  if root ~= home and vim.fs.dirname(root) ~= root then
    on_dir(root)
  end
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "ruby" } },
  },
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "ruby-lsp", "rubocop", "rdbg" } },
  },
  {
    "neovim/nvim-lspconfig",
    -- A function: ruby-lsp and Bundler are looked for when nvim-lspconfig loads, not at every startup.
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers.ruby_lsp = vim.tbl_deep_extend("force", opts.servers.ruby_lsp or {}, {
        -- ruby-lsp requires Bundler at start; without it the server would only fail to spawn.
        enabled = vim.fn.executable("ruby-lsp") == 1 and vim.fn.executable("bundle") == 1,
        -- Without BUNDLE_GEMFILE, ruby-lsp writes .ruby-lsp/ into the project and installs and updates gems from
        -- the network at every start. Set, it runs on Mason's pinned gems only.
        cmd = function(dispatchers, config)
          local root = config and config.root_dir

          return vim.lsp.rpc.start({ "ruby-lsp" }, dispatchers, {
            cwd = config and config.cmd_cwd or root,
            env = { BUNDLE_GEMFILE = vim.fs.joinpath(root or vim.fn.getcwd(), "Gemfile") },
          })
        end,
        root_dir = ruby_root,
        -- rubocop runs as its own server: Mason's rubocop is not on ruby-lsp's gem path.
        init_options = { formatter = "none", linters = {} },
      })

      opts.servers.rubocop = vim.tbl_deep_extend("force", opts.servers.rubocop or {}, { root_dir = ruby_root })
    end,
  },
  {
    "mfussenegger/nvim-dap",
    optional = true,
    opts = function()
      local dap = require("dap")
      local rdbg = require("features.lsp.mason").bin("rdbg")

      -- Without rdbg Ruby offers no debug configuration rather than one that fails to start. Nor on Windows: rdbg
      -- serves a Unix socket, which Neovim reaches there only as a named pipe, or TCP, which any local process could
      -- reach and drive (no authentication; rdbg outlives Neovim when started through Mason's .cmd).
      if vim.fn.has("win32") == 1 or vim.fn.executable(rdbg) ~= 1 then
        return
      end

      -- rdbg serves DAP on a Unix socket in Neovim's private temp folder, never on TCP. It waits for the client;
      -- the attach request's nonstop says whether to stop at the first line.
      dap.adapters.rdbg = dap.adapters.rdbg
        or function(callback, config)
          local socket = vim.fn.tempname() .. ".sock"
          local args = { "--open", "--sock-path=" .. socket, "--", config.program }

          vim.list_extend(args, config.args or {})
          callback({
            type = "pipe",
            pipe = socket,
            executable = { command = rdbg, args = args, cwd = config.cwd },
          })
        end

      dap.configurations.ruby = dap.configurations.ruby
        or {
          {
            type = "rdbg",
            name = "rdbg: this file",
            request = "attach",
            program = "${file}",
            cwd = "${fileDirname}",
            nonstop = true,
            localfs = true,
          },
          {
            type = "rdbg",
            name = "rdbg: this file, stop at the first line",
            request = "attach",
            program = "${file}",
            cwd = "${fileDirname}",
            nonstop = false,
            localfs = true,
          },
          {
            type = "rdbg",
            name = "rdbg: this file with arguments",
            request = "attach",
            program = "${file}",
            cwd = "${fileDirname}",
            args = function()
              return require("dap.utils").splitstr(vim.fn.input("Arguments: "))
            end,
            nonstop = true,
            localfs = true,
          },
        }
    end,
  },
}
