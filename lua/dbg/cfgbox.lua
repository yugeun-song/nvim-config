local M = {}

-- The box view: one box per basic block, ranks stacked, branches drawn between
-- them.  Calls stay as text inside their block, as in IDA and Binary Ninja: a
-- call returns, so the block continues through it, and drawing every one turns
-- the picture into a hairball.
--
-- Rank and order arrive from the analyser; only the mapping to cells is here.

-- Limits, set from measurement rather than taste.  The canvas is materialised
-- cell by cell, so its area is the cost: on this machine 1.5M cells is about
-- 340 ms, which is a repaint you do not notice, and the next step up was
-- multi-second.  Raise M.canvas_cells for bigger graphs on a faster machine;
-- lower it if a repaint ever feels slow.
--
-- The width cap matters more than it looks: one long operand in one block widens
-- its whole rank, and rank width multiplies into the area.
M.canvas_cells = 1500000
M.box_inner_max = 56

local GAP_X = 3 -- blank columns between neighbouring boxes
local CHANNEL = 3 -- rows reserved between rank bands for edge routing
local MARGIN = 3 -- columns kept clear each side for the skip and back-edge lanes

local GLYPH = {
  tl = "┌",
  tr = "┐",
  bl = "└",
  br = "┘",
  h = "─",
  v = "│",
  down = "▼",
  cross = "┼",
  tee_d = "┬",
  tee_u = "┴",
  tee_r = "├",
  tee_l = "┤",
}

local STATE_HL = {
  current = "DbgStopSign",
  executed = "DbgBranchTaken",
  ["will-execute"] = "DbgBranchTaken",
  unknown = "DbgMuted",
  unreachable = "DbgMuted",
}

local EDGE_HL = {
  ["true"] = "DbgBranchTaken",
  ["false"] = "DbgError",
  uncond = "DbgAddr",
  fall = "DbgMuted",
}

-- A terminal cell holds one colour, so where two edges cross only one of them
-- can be drawn.  Which one is decided here rather than by whichever happened to
-- be painted last: the edge that carries more information wins, so the line you
-- can follow across a crossing is always the more important one.
local EDGE_PRIORITY = {
  ["true"] = 130,
  ["false"] = 125,
  uncond = 120,
  fall = 115,
}
local BOX_PRIORITY = 140

local function blank(rows, cols)
  local grid = {}
  for r = 1, rows do
    local line = {}
    for c = 1, cols do
      line[c] = " "
    end
    grid[r] = line
  end
  return grid
end

local function put(grid, r, c, ch)
  local line = grid[r]
  if line and c >= 1 and c <= #line then
    line[c] = ch
  end
end

-- Crossing rather than erasing, so overlapping edges stay readable.
local function put_v(grid, r, c)
  local line = grid[r]
  if not (line and c >= 1 and c <= #line) then
    return
  end
  local at = line[c]
  if at == " " then
    line[c] = GLYPH.v
  elseif at == GLYPH.h then
    line[c] = GLYPH.cross
  end
end

local function put_h(grid, r, c)
  local line = grid[r]
  if not (line and c >= 1 and c <= #line) then
    return
  end
  local at = line[c]
  if at == " " then
    line[c] = GLYPH.h
  elseif at == GLYPH.v then
    line[c] = GLYPH.cross
  end
end

-- One orthogonal run, corners included: without them the three strokes read as
-- three unrelated lines instead of one edge.
-- One cell per row: a vertical run needs a span for every row it crosses, or the
-- edge is coloured along its horizontal and plain along its verticals, which
-- reads as a line that stops halfway.
local function paint_column(hl, from, to, col, group)
  for r = math.min(from, to), math.max(from, to) do
    hl[#hl + 1] = { r, col, col + 1, group, EDGE_PRIORITY[group] or 110 }
  end
end

-- The tee only goes on an actual border cell.  The terminator label lives in the
-- top border, and writing through it produces things like "[bra<tee>ch]"; the
-- arrowhead above already says where the edge lands.
local BORDER = { [GLYPH.h] = true, [GLYPH.tl] = true, [GLYPH.tr] = true, [GLYPH.tee_u] = true }

local function land_tee(grid, row, col)
  local line = grid[row]
  if line and line[col] and BORDER[line[col]] then
    line[col] = GLYPH.tee_u
  end
end

local function route_edge(grid, hl, sx, sy, dx, dy, route, group, arrow_group)
  put(grid, sy, sx, GLYPH.tee_d)
  hl[#hl + 1] = { sy, sx, sx + 1, group, EDGE_PRIORITY[group] or 110 }
  if sx == dx then
    for r = sy + 1, dy - 2 do
      put_v(grid, r, sx)
    end
    paint_column(hl, sy + 1, dy - 2, sx, group)
  else
    for r = sy + 1, route - 1 do
      put_v(grid, r, sx)
    end
    paint_column(hl, sy + 1, route, sx, group)
    put(grid, route, sx, dx > sx and GLYPH.bl or GLYPH.br)
    for c = math.min(sx, dx) + 1, math.max(sx, dx) - 1 do
      put_h(grid, route, c)
    end
    put(grid, route, dx, dx > sx and GLYPH.tr or GLYPH.tl)
    for r = route + 1, dy - 2 do
      put_v(grid, r, dx)
    end
    paint_column(hl, route, dy - 2, dx, group)
    hl[#hl + 1] = { route, math.min(sx, dx), math.max(sx, dx) + 1, group, EDGE_PRIORITY[group] or 110 }
  end
  put(grid, dy - 1, dx, GLYPH.down)
  land_tee(grid, dy, dx)
  hl[#hl + 1] = { dy - 1, dx, dx + 1, arrow_group or group, EDGE_PRIORITY[group] or 110 }
end

-- The text inside one block: its instructions, and the addresses they are at.
-- Zoom in a character grid is level of detail: there is no half a cell.  Level 2
-- is everything, level 0 is a label, and the boxes narrow as the level drops so
-- a wide graph fits.
M.DETAIL_MAX = 2

local function block_body(data, block, detail)
  local body = {}
  if detail == 0 then
    local pc = ""
    for i = block.first + 1, block.last + 1 do
      local insn = data.insns[i]
      if type(insn) == "table" and insn.is_pc then
        pc = " <"
      end
    end
    local n = block.last - block.first + 1
    body[1] = ("  b%d  %d insn%s%s"):format(block.id, n, n == 1 and "" or "s", pc)
    return body
  end
  for i = block.first + 1, block.last + 1 do
    local insn = data.insns[i]
    if type(insn) == "table" then
      local mark = insn.is_pc and "> " or "  "
      if detail == 1 then
        body[#body + 1] = ("%s%-7s %s"):format(mark, insn.mnemonic or "", insn.operands or "")
      else
        body[#body + 1] = ("%s%s  %-7s %s"):format(
          mark,
          (insn.addr or ""):gsub("^0x", ""),
          insn.mnemonic or "",
          insn.operands or ""
        )
      end
    end
  end
  if #body == 0 then
    body[1] = "  (empty)"
  end
  return body
end

local function usable(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function M.render(data, width, detail)
  if type(data) ~= "table" or type(data.blocks) ~= "table" or type(data.insns) ~= "table" then
    return nil
  end
  local blocks = {}
  for _, b in ipairs(data.blocks) do
    if
      type(b) == "table"
      and usable(b.id)
      and usable(b.rank)
      and usable(b.order)
      and usable(b.first)
      and usable(b.last)
    then
      blocks[#blocks + 1] = b
    end
  end
  if #blocks == 0 then
    return nil
  end

  -- Measure every box, then place the ranks.
  local boxes = {}
  local by_rank = {}
  for _, b in ipairs(blocks) do
    local body = block_body(data, b, detail or M.DETAIL_MAX)
    local inner = 0
    for _, l in ipairs(body) do
      inner = math.max(inner, vim.fn.strchars(l))
    end
    local title = (b.terminator and ("[" .. b.terminator .. "]") or "")
    inner = math.max(inner, vim.fn.strchars(title) + 2)
    if inner > M.box_inner_max then
      inner = M.box_inner_max
      for i, l in ipairs(body) do
        if vim.fn.strchars(l) > inner then
          body[i] = vim.fn.strcharpart(l, 0, inner - 1) .. "~"
        end
      end
    end
    boxes[b.id] = { block = b, body = body, w = inner + 4, h = #body + 2, title = title }
    by_rank[b.rank] = by_rank[b.rank] or {}
    table.insert(by_rank[b.rank], b.id)
  end

  local ranks = vim.tbl_keys(by_rank)
  table.sort(ranks)
  for _, r in ipairs(ranks) do
    table.sort(by_rank[r], function(x, y)
      return boxes[x].block.order < boxes[y].block.order
    end)
  end

  -- Widest rank sets the canvas; the rest are centred against it.
  local canvas_w = 0
  for _, r in ipairs(ranks) do
    local w = 0
    for i, id in ipairs(by_rank[r]) do
      w = w + boxes[id].w + (i > 1 and GAP_X or 0)
    end
    canvas_w = math.max(canvas_w, w)
  end
  canvas_w = math.max(canvas_w, 20) + 2 * MARGIN

  local y = 1
  for _, r in ipairs(ranks) do
    local w = 0
    for i, id in ipairs(by_rank[r]) do
      w = w + boxes[id].w + (i > 1 and GAP_X or 0)
    end
    local x = math.max(MARGIN + 1, math.floor((canvas_w - w) / 2) + 1)
    local tallest = 0
    for _, id in ipairs(by_rank[r]) do
      boxes[id].x, boxes[id].y = x, y
      x = x + boxes[id].w + GAP_X
      tallest = math.max(tallest, boxes[id].h)
    end
    -- Routing starts below the tallest box in the rank: keyed off each box's
    -- own bottom, a short box's row would cross the taller box beside it.
    for _, id in ipairs(by_rank[r]) do
      boxes[id].rank_bottom = y + tallest - 1
    end
    y = y + tallest + CHANNEL + 1
  end
  local canvas_h = y

  if canvas_w * canvas_h > M.canvas_cells then
    return nil,
      nil,
      nil,
      ("This function needs a %d x %d canvas, past what the view will draw. Press - for less detail."):format(
        canvas_w,
        canvas_h
      )
  end

  local grid = blank(canvas_h, canvas_w)
  local hl = {}

  -- Boxes.
  for _, b in ipairs(blocks) do
    local box = boxes[b.id]
    local x, yy, w, h = box.x, box.y, box.w, box.h
    put(grid, yy, x, GLYPH.tl)
    put(grid, yy, x + w - 1, GLYPH.tr)
    put(grid, yy + h - 1, x, GLYPH.bl)
    put(grid, yy + h - 1, x + w - 1, GLYPH.br)
    for c = x + 1, x + w - 2 do
      put(grid, yy, c, GLYPH.h)
      put(grid, yy + h - 1, c, GLYPH.h)
    end
    for r = yy + 1, yy + h - 2 do
      put(grid, r, x, GLYPH.v)
      put(grid, r, x + w - 1, GLYPH.v)
    end
    -- Terminator in the top border: readable without finding the last row.
    if box.title ~= "" then
      local tx = x + w - 2 - vim.fn.strchars(box.title)
      for i = 1, vim.fn.strchars(box.title) do
        put(grid, yy, tx + i - 1, vim.fn.strcharpart(box.title, i - 1, 1))
      end
    end
    for i, line in ipairs(box.body) do
      for cidx = 1, vim.fn.strchars(line) do
        put(grid, yy + i, x + 1 + cidx, vim.fn.strcharpart(line, cidx - 1, 1))
      end
    end
    local group = STATE_HL[b.state] or "DbgMuted"
    for r = yy, yy + h - 1 do
      hl[#hl + 1] = { r, x, x + 1, group, BOX_PRIORITY }
      hl[#hl + 1] = { r, x + w - 1, x + w, group, BOX_PRIORITY }
    end
    hl[#hl + 1] = { yy, x, x + w, group, BOX_PRIORITY }
    hl[#hl + 1] = { yy + h - 1, x, x + w, group, BOX_PRIORITY }
  end

  -- Three routing cases: next rank goes down the band; a rank-skipping edge
  -- takes the right margin so it does not cross the boxes between; a back edge
  -- takes the left, which is where every assembly graph view puts loops.
  local edges = {}
  for _, e in ipairs(type(data.block_edges) == "table" and data.block_edges or {}) do
    if type(e) == "table" and boxes[e.from] and boxes[e.to] then
      edges[#edges + 1] = e
    end
  end

  -- Spread arrivals across the target's top border; landing them all on the
  -- centre column makes two edges into one box look like one.
  local departure

  local function arrival(e)
    local ins, outs = {}, {}
    for _, ee in ipairs(edges) do
      if ee.to == e.to then
        ins[#ins + 1] = ee
      end
      if ee.from == e.from then
        outs[#outs + 1] = ee
      end
    end
    local slot = 1
    for k, ee in ipairs(ins) do
      if ee == e then
        slot = k
      end
    end
    local dst = boxes[e.to]
    -- The only way out of one box into the only way into another: keep the
    -- column so the edge is a straight line rather than a jog for no reason.
    if #ins == 1 and #outs == 1 then
      local sx = departure(e)
      if sx > dst.x and sx < dst.x + dst.w - 1 then
        return sx
      end
    end
    return dst.x + math.floor(dst.w * slot / (#ins + 1))
  end

  departure = function(e)
    local outs = {}
    for _, ee in ipairs(edges) do
      if ee.from == e.from then
        outs[#outs + 1] = ee
      end
    end
    local slot = 1
    for k, ee in ipairs(outs) do
      if ee == e then
        slot = k
      end
    end
    local src = boxes[e.from]
    return src.x + math.floor(src.w * slot / (#outs + 1)), #outs
  end

  -- Route rows inside a band, one per edge, so two edges leaving the same rank
  -- never share a horizontal.
  local band_rows = {}
  for _, e in ipairs(edges) do
    local src, dst = boxes[e.from], boxes[e.to]
    if src and dst and not e.back and dst.y > src.y then
      local key = src.rank_bottom
      band_rows[key] = band_rows[key] or {}
      table.insert(band_rows[key], e)
    end
  end

  local right_lane = canvas_w - 1
  local left_lane = 1

  -- Down out of the source, along to a margin lane, down past everything in
  -- between, back in to the target.
  local function route_via_lane(e, lane, group)
    local src, dst = boxes[e.from], boxes[e.to]
    local sx = departure(e)
    local dx = arrival(e)
    local sy = src.y + src.h - 1
    local dy = dst.y
    local turn, land = src.rank_bottom + 1, dy - 1
    put(grid, sy, sx, GLYPH.tee_d)
    for r = sy + 1, turn - 1 do
      put_v(grid, r, sx)
    end
    put(grid, turn, sx, lane > sx and GLYPH.bl or GLYPH.br)
    for c = math.min(sx, lane) + 1, math.max(sx, lane) - 1 do
      put_h(grid, turn, c)
    end
    put(grid, turn, lane, lane > sx and GLYPH.tr or GLYPH.tl)
    for r = math.min(turn, land) + 1, math.max(turn, land) - 1 do
      put_v(grid, r, lane)
    end
    put(grid, land, lane, land > turn and (lane > dx and GLYPH.br or GLYPH.bl) or (lane > dx and GLYPH.tr or GLYPH.tl))
    for c = math.min(dx, lane) + 1, math.max(dx, lane) - 1 do
      put_h(grid, land, c)
    end
    put(grid, land, dx, lane > dx and GLYPH.tl or GLYPH.tr)
    put(grid, dy - 1, dx, GLYPH.down)
    land_tee(grid, dy, dx)
    hl[#hl + 1] = { turn, math.min(sx, lane), math.max(sx, lane) + 1, group, EDGE_PRIORITY[group] or 110 }
    hl[#hl + 1] = { land, math.min(dx, lane), math.max(dx, lane) + 1, group, EDGE_PRIORITY[group] or 110 }
    paint_column(hl, sy, turn, sx, group)
    paint_column(hl, turn, land, lane, group)
    paint_column(hl, land, dy - 1, dx, group)
  end

  for _, e in ipairs(edges) do
    local src, dst = boxes[e.from], boxes[e.to]
    if src and dst then
      local group = EDGE_HL[e.kind] or "DbgMuted"
      if e.back or dst.y <= src.y then
        route_via_lane(e, left_lane, "DbgWarn")
      elseif (dst.block.rank - src.block.rank) > 1 then
        route_via_lane(e, right_lane, group)
      else
        local sx = departure(e)
        local dx = arrival(e)
        local sy = src.y + src.h - 1
        local dy = dst.y
        local key = src.rank_bottom
        local slot = 1
        for k, ee in ipairs(band_rows[key] or {}) do
          if ee == e then
            slot = k
          end
        end
        local base = src.rank_bottom
        for r = sy + 1, base do
          put_v(grid, r, sx)
        end
        local route = math.max(base + 1, math.min(base + slot, dy - 2))
        route_edge(grid, hl, sx, sy, dx, dy, route, group)
      end
    end
  end

  local lines = {}
  for r = 1, canvas_h do
    lines[r] = (table.concat(grid[r]):gsub("%s+$", ""))
  end
  -- The last rank's channel has nothing to route.
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end
  -- Extmark columns are byte offsets; the grid is cells.
  local out_hl = {}
  for _, h in ipairs(hl) do
    local line = lines[h[1]]
    if line then
      local s = vim.fn.byteidx(line, math.min(h[2] - 1, vim.fn.strchars(line)))
      local e = vim.fn.byteidx(line, math.min(h[3] - 1, vim.fn.strchars(line)))
      if s and e and s >= 0 and e > s then
        out_hl[#out_hl + 1] = { h[1] - 1, s, e, h[4], h[5] }
      end
    end
  end
  local where = {}
  for _, b in ipairs(blocks) do
    local box = boxes[b.id]
    where[b.id] = { row = box.y, col = box.x, height = box.h, width = box.w }
  end
  return lines, out_hl, where
end

return M
