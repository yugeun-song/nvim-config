return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
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
  end,
}
