-- C and C++: clangd, cscope and tags tuned for big trees, gf on #include, indentation from the project and
-- clang-format without autoformat, every #if branch on request, and Visual Studio projects on Windows. The code
-- lives in lua/features/lang/c/.
local function clang_format_fallback(buf)
  local bo = vim.bo[buf]
  local width = bo.shiftwidth > 0 and bo.shiftwidth or bo.tabstop

  return ("{BasedOnStyle: LLVM, IndentWidth: %d, TabWidth: %d, UseTab: %s, BreakBeforeBraces: Custom, BraceWrapping: {AfterFunction: true}, AllowShortFunctionsOnASingleLine: None, SortIncludes: Never}"):format(
    width,
    bo.tabstop,
    bo.expandtab and "Never" or "ForIndentation"
  )
end

local specs = {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "c", "cpp" } },
  },
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "clangd", "clang-format" } },
  },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local clangd = require("features.lang.c.clangd")
      local tmp = clangd.private_tmp()

      opts.servers = opts.servers or {}
      opts.servers.clangd = vim.tbl_deep_extend("force", opts.servers.clangd or {}, {
        -- Not through Mason: its clangd exists only for x64 Linux (glibc), x64 Windows and macOS; PATH serves the rest.
        mason = false,
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
          "-j=" .. vim.uv.available_parallelism(),
        },
        cmd_env = { TMPDIR = tmp, TMP = tmp, TEMP = tmp },
        -- A buffer with no file (:enew, then a C filetype) has no URI clangd can read, and it would refuse every
        -- request ("unresolvable URI"). Others find their root by the root markers, as Neovim does without this.
        root_dir = function(bufnr, on_dir)
          if vim.api.nvim_buf_get_name(bufnr) ~= "" then
            on_dir(vim.fs.root(bufnr, vim.lsp.config.clangd.root_markers or {}))
          end
        end,
      })

      if vim.fn.has("win32") == 1 then
        local flag = clangd.query_driver()

        if flag then
          table.insert(opts.servers.clangd.cmd, flag)
        end
      end
    end,
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        c = { "clang_format" },
        cpp = { "clang_format" },
      },
      formatters = {
        clang_format = {
          prepend_args = function(_, ctx)
            local found = vim.fs.find({ ".clang-format", "_clang-format" }, {
              upward = true,
              path = ctx.dirname,
              type = "file",
            })[1]

            if found then
              return {}
            end

            return { "--style=" .. clang_format_fallback(ctx.buf) }
          end,
        },
      },
    },
  },
  {
    "dhananjaylatkar/cscope_maps.nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
    -- Its commands and keys load it, and so does gd in assembler asking for cscope's answers (require loads it).
    cmd = { "Cs", "Cscope", "Cstag" },
    keys = {
      { "<leader>is", [[<cmd>exe "Cscope find s " . expand("<cword>")<cr>]], desc = "Cscope: Find Symbol" },
      { "<leader>ig", [[<cmd>exe "Cscope find g " . expand("<cword>")<cr>]], desc = "Cscope: Find Global Def" },
      { "<leader>ic", [[<cmd>exe "Cscope find c " . expand("<cword>")<cr>]], desc = "Cscope: Find Callers" },
      { "<leader>id", [[<cmd>exe "Cscope find d " . expand("<cword>")<cr>]], desc = "Cscope: Find Callees" },
      { "<leader>it", [[<cmd>exe "Cscope find t " . expand("<cword>")<cr>]], desc = "Cscope: Find Text" },
      { "<leader>ie", [[<cmd>exe "Cscope find e " . expand("<cword>")<cr>]], desc = "Cscope: Find Egrep" },
      { "<leader>if", [[<cmd>exe "Cscope find f " . expand("<cfile>")<cr>]], desc = "Cscope: Find File" },
      { "<leader>ii", [[<cmd>exe "Cscope find i " . expand("<cfile>")<cr>]], desc = "Cscope: Find Includes" },
      { "<leader>ia", [[<cmd>exe "Cscope find a " . expand("<cword>")<cr>]], desc = "Cscope: Find Assignments" },
    },
    opts = {
      disable_maps = true,
      cscope = {
        db_file = {},
        picker = "telescope",
        tag = {
          keymap = false,
        },
      },
    },
    config = function(_, opts)
      require("cscope_maps").setup(opts)

      local cscope = require("cscope")
      local get_result = cscope.get_result

      ---@diagnostic disable-next-line: duplicate-set-field
      cscope.get_result = function(op_n, op_s, symbol, hide_log)
        local navigation = require("features.lang.asm.definition_navigation")
        local database = navigation.cscope_database()

        vim.g.cscope_maps_db_file = database and database .. "::@" or nil

        local rc, hits = get_result(op_n, op_s, symbol, hide_log)

        if op_s ~= "g" or not hits then
          return rc, hits
        end

        local kept = navigation.real_definitions(hits, symbol)

        return rc, #kept > 0 and kept or hits
      end
    end,
  },
  {
    -- Indentation, gf on #include and tags over the language server's tagfunc, with the first buffer they serve
    -- (lua/features/lang/c/init.lua).
    "c_and_cpp",
    virtual = true,
    ft = require("features.lang.c").FILETYPES,
    config = function()
      require("features.lang.c").setup()
    end,
  },
  {
    "all_ifdef_branches",
    virtual = true,
    -- With the first C-family buffer: its state-file watcher has nothing to do before one.
    ft = require("features.lang.c.all_ifdef_branches.filetypes"),
    config = function()
      local ifdef_all = require("features.lang.c.all_ifdef_branches")

      ifdef_all.setup()
      Snacks.toggle({
        name = "All #if Branches",
        get = function()
          return ifdef_all.enabled
        end,
        set = ifdef_all.set,
      }):map("<leader>uB")
    end,
  },
}

-- Windows only: compile_commands.json from a Visual Studio project, rebuilt when it falls behind
-- (lua/features/lang/c/msvc_toolchain/compile_database.lua).
if vim.fn.has("win32") == 1 then
  specs[#specs + 1] = {
    "msvc_compile_database",
    virtual = true,
    cmd = "MsvcCompileDb",
    ft = { "c", "cpp", "cuda" },
    config = function()
      local db = require("features.lang.c.msvc_toolchain.compile_database")
      local group = vim.api.nvim_create_augroup("msvc_compile_database", { clear = true })

      vim.api.nvim_create_user_command("MsvcCompileDb", function(args)
        db.generate({ configuration = args.fargs[1], platform = args.fargs[2] })
      end, {
        nargs = "*",
        -- The solution's own configurations and platforms, as its last database found them.
        complete = function(lead, line)
          return vim.tbl_filter(function(name)
            return vim.startswith(name:lower(), lead:lower())
          end, db.complete(line))
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
end

return specs
