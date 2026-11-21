-- The statusline: the full path, an encoding and line-ending flag, and the latest git tag after the branch. Text from a
-- repository is shown in it, in bufferline's tabline and in snacks' picker input, never run (lua/features/ui/statusline.lua).
return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      local statusline = require("features.ui.statusline")

      opts.sections.lualine_c[4] = { LazyVim.lualine.pretty_path({ length = 0 }) }

      local FMT_LABEL = { unix = "LF", dos = "CRLF", mac = "CR" }
      local cache = {}

      local function file_format_flag()
        local ok, result = pcall(function()
          local buf = vim.api.nvim_get_current_buf()
          local hit = cache[buf]

          if hit ~= nil then
            return hit
          end

          local enc = vim.bo[buf].fileencoding

          if enc == nil or enc == "" then
            enc = vim.o.encoding or ""
          end

          local ff = vim.bo[buf].fileformat or ""
          local label = FMT_LABEL[ff] or ff
          local bom = vim.bo[buf].bomb and "+BOM" or ""

          local val

          if enc == "" and label == "" then
            val = ""
          else
            val = string.format("%s%s/%s", enc:upper(), bom, label)
          end

          cache[buf] = val

          return val
        end)

        if not ok or type(result) ~= "string" then
          return ""
        end

        return result
      end

      local group = vim.api.nvim_create_augroup("LualineFileFormatFlag", { clear = true })

      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "BufFilePost" }, {
        group = group,
        callback = function(args)
          cache[args.buf] = nil
        end,
      })

      vim.api.nvim_create_autocmd("OptionSet", {
        group = group,
        pattern = { "fileencoding", "fileformat", "bomb" },
        callback = function()
          cache[vim.api.nvim_get_current_buf()] = nil
        end,
      })

      vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = group,
        callback = function(args)
          cache[args.buf] = nil
        end,
      })

      table.insert(opts.sections.lualine_y, 1, {
        file_format_flag,
        cond = function()
          local bt = vim.bo.buftype

          return bt == "" or bt == "acwrite"
        end,
        padding = { left = 1, right = 1 },
      })

      -- After the branch, the latest git tag (lua/features/ui/statusline.lua).
      statusline.add_git_tag(opts)

      -- LazyVim's components, these and the extensions'; a component added later (the IME marks) escapes its own text.
      statusline.sanitize_components(opts)
      statusline.guard_git_branch()
    end,
  },
  {
    "akinsho/bufferline.nvim",
    optional = true,
    opts = function()
      require("features.ui.statusline").guard_bufferline()
    end,
  },
  {
    "folke/snacks.nvim",
    opts = function()
      require("features.ui.statusline").guard_snacks_input()
    end,
  },
}
