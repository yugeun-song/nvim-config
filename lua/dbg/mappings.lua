local panel = require("dbg.panel")
local gdbq = require("dbg.gdbq")
local ui = require("dbg.ui")

local M = {}

local rows = {}
local note = nil

function M.buffer()
  local buf, created = panel.buffer("mappings", "dbg-mappings")
  if created then
    vim.keymap.set("n", "r", function()
      M.probe()
    end, { buffer = buf, nowait = true, desc = "Mappings: refresh" })
    vim.keymap.set("n", "<CR>", function()
      local line = vim.api.nvim_get_current_line()
      local start = line:match("^%s*(0x%x+)")
      if start then
        require("dbg.memory").show_expr(start, "target")
        require("dbg.layout").focus("memory")
      end
    end, { buffer = buf, nowait = true, desc = "Mappings: open region in the hex view" })
  end
  return buf
end

local function classify(name, perm)
  name = name or ""
  if name:find("%[stack%]") then
    return "DbgStack"
  end
  if name:find("heap") then
    return "DbgData"
  end
  if perm and perm:find("x") then
    return "DbgCode"
  end
  if name:find("%.bss") or name:find("%.data") then
    return "DbgData"
  end
  return "DbgValue"
end

function M.render()
  local buf = M.buffer()
  local width = panel.width(buf, 100)
  local banner = ui.banner("MAPPINGS", width, ("%d regions"):format(#rows))
  local lines = { banner }
  local hls = ui.banner_hl(0, banner, "MAPPINGS")
  if note then
    lines[#lines + 1] = "  " .. note
    hls[#hls + 1] = { #lines - 1, 0, 200, "DbgMuted" }
  end
  if #rows == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  No mapping information. Press r to query the target."
    panel.render(buf, lines, hls)
    return
  end
  lines[#lines + 1] = ("  %-18s %-18s %-5s %-10s %s"):format("start", "end", "perm", "size", "name")
  hls[#hls + 1] = { #lines - 1, 0, 200, "DbgMuted" }
  for _, r in ipairs(rows) do
    lines[#lines + 1] = ("  %-18s %-18s %-5s %-10s %s"):format(r.start, r.stop, r.perm, r.size, r.name)
    local ln = #lines - 1
    hls[#hls + 1] = { ln, 2, 20, "DbgAddr" }
    hls[#hls + 1] = { ln, 21, 39, "DbgAddr" }
    hls[#hls + 1] = { ln, 58, 200, classify(r.name, r.perm) }
  end
  panel.render(buf, lines, hls)
end

function M.probe()
  local session = gdbq.session()
  if not session then
    rows, note = {}, "No debug session is running."
    M.render()
    return
  end
  gdbq.run("vmmap", function(text, err)
    vim.schedule(function()
      rows = {}
      if not text then
        note = "vmmap is unavailable: " .. tostring(err)
        M.render()
        return
      end
      if text:find("Undefined command") then
        note = "vmmap needs pwndbg; falling back to 'info files' is not implemented."
        M.render()
        return
      end
      note = nil
      for line in text:gmatch("[^\n]+") do
        local a, b, perm, size, rest = line:match("^%s*(0x%x+)%s+(0x%x+)%s+(%S+)%s+(%x+)%s*(.*)$")
        if a then
          local offset, name = rest:match("^(%x+)%s*(.*)$")
          rows[#rows + 1] = {
            start = a,
            stop = b,
            perm = perm,
            size = "0x" .. size,
            name = (name and name ~= "" and name) or (offset and offset ~= "" and "" or rest) or "",
          }
        end
      end
      if #rows == 0 then
        note = "vmmap returned no parsable rows."
      end
      M.render()
    end)
  end)
end

function M.open()
  local buf = M.buffer()
  panel.show(buf, 14, "Mappings")
  M.probe()
end

return M
