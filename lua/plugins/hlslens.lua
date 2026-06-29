local function override_lens(render, pos_list, nearest, idx, rel_idx)
  local sfw = vim.v.searchforward == 1
  local abs_rel_idx = math.abs(rel_idx)
  local indicator
  if abs_rel_idx > 1 then
    indicator = ("%d%s"):format(abs_rel_idx, sfw ~= (rel_idx > 1) and "N" or "n")
  elseif abs_rel_idx == 1 then
    indicator = sfw ~= (rel_idx == 1) and "N" or "n"
  else
    indicator = ""
  end

  local entry = pos_list[idx]
  local lnum, col = entry[1], entry[2]
  local text, chunks
  if nearest then
    local cur, total = idx, #pos_list
    local ok, sc = pcall(vim.fn.searchcount, { recompute = true, maxcount = 0, timeout = 500 })
    if ok and type(sc) == "table" and sc.incomplete == 0 and (sc.total or 0) > 0 then
      cur, total = sc.current, sc.total
    end
    if indicator ~= "" then
      text = ("[%s %d/%d]"):format(indicator, cur, total)
    else
      text = ("[%d/%d]"):format(cur, total)
    end
    chunks = { { " " }, { text, "HlSearchLensNear" } }
  else
    text = ("[%s %d]"):format(indicator, idx)
    chunks = { { " " }, { text, "HlSearchLens" } }
  end
  render.setVirt(0, lnum - 1, col - 1, chunks, nearest)
end

local function hlslens_search(forward_key, backward_key)
  return function()
    local key = vim.v.searchforward == 1 and forward_key or backward_key
    local ok, err = pcall(vim.cmd, ("normal! %d%szv"):format(vim.v.count1, key))
    if ok then
      pcall(function()
        require("hlslens").start()
      end)
    elseif err then
      vim.api.nvim_echo({ { err:match("E%d+:.*") or err, "ErrorMsg" } }, false, {})
    end
  end
end

return {
  "kevinhwang91/nvim-hlslens",
  event = "VeryLazy",
  opts = {
    calm_down = false,
    nearest_only = true,
    nearest_float_when = "auto",
    override_lens = override_lens,
  },
  config = function(_, opts)
    require("hlslens").setup(opts)
    vim.api.nvim_create_autocmd("CmdlineLeave", {
      group = vim.api.nvim_create_augroup("hlslens_incsearch", { clear = true }),
      pattern = { "/", "?" },
      callback = function()
        pcall(function()
          require("hlslens").start()
        end)
      end,
    })
  end,
  keys = {
    { "n", mode = "n", hlslens_search("n", "N"), desc = "Next Search Result" },
    { "N", mode = "n", hlslens_search("N", "n"), desc = "Prev Search Result" },
    { "*", mode = "n", [[*<Cmd>lua require('hlslens').start()<CR>]], desc = "Search Word Forward" },
    { "#", mode = "n", [[#<Cmd>lua require('hlslens').start()<CR>]], desc = "Search Word Backward" },
    { "g*", mode = "n", [[g*<Cmd>lua require('hlslens').start()<CR>]], desc = "Search Partial Word Forward" },
    { "g#", mode = "n", [[g#<Cmd>lua require('hlslens').start()<CR>]], desc = "Search Partial Word Backward" },
  },
}
