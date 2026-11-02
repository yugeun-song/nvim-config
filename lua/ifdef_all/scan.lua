local M = {}

local DIRECTIVE = {
  ["if"] = "open",
  ifdef = "open",
  ifndef = "open",
  elif = "mid",
  elifdef = "mid",
  elifndef = "mid",
  ["else"] = "mid",
  endif = "close",
}

local function strip_cr(s)
  return (s:gsub("\r$", ""))
end

local function comment_open_after(line, open)
  local i, n = 1, #line
  while i <= n do
    if open then
      local e = line:find("*/", i, true)
      if not e then
        return true
      end
      i, open = e + 2, false
    else
      local s = line:find("[\"'/]", i)
      if not s then
        return false
      end
      local c = line:sub(s, s)
      if c == "/" then
        local d = line:sub(s + 1, s + 1)
        if d == "/" then
          return false
        end
        open = d == "*"
        i = s + (open and 2 or 1)
      else
        local pat = c == '"' and '[\\"]' or "[\\']"
        local j = s + 1
        while true do
          local k = line:find(pat, j)
          if not k then
            return false
          end
          if line:sub(k, k) == "\\" then
            j = k + 2
          else
            i = k + 1
            break
          end
        end
      end
    end
  end
  return open
end

local function normalize(text)
  return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

function M.parse(lines)
  local chains, roots, ctx = {}, {}, {}
  local stack = {}
  local open = false
  local n = #lines
  local i = 1
  while i <= n do
    local text = strip_cr(lines[i])
    local kw = not open and text:match("^%s*#%s*(%a+)") or nil
    local kind = kw and DIRECTIVE[kw]
    local last = i
    if kind then
      while last < n and strip_cr(lines[last]):match("\\$") do
        last = last + 1
      end
    end
    for j = i, last do
      open = comment_open_after(strip_cr(lines[j]), open)
    end
    local top = stack[#stack]
    local here = top and { top.id, #top.branches } or nil
    local owner = here
    if kind == "open" then
      local c = {
        id = #chains + 1,
        parent = here,
        text = { normalize(text) },
        branches = { { kind = kw, dline = i - 1, dlast = last - 1, children = {} } },
      }
      chains[c.id] = c
      if top then
        table.insert(top.branches[#top.branches].children, c.id)
      else
        roots[#roots + 1] = c.id
      end
      stack[#stack + 1] = c
    elseif kind == "mid" and top then
      top.branches[#top.branches].blast = i - 2
      top.branches[#top.branches + 1] = { kind = kw, dline = i - 1, dlast = last - 1, children = {} }
      top.text[#top.text + 1] = normalize(text)
      owner = top.parent
    elseif kind == "close" and top then
      top.branches[#top.branches].blast = i - 2
      top.eline = i - 1
      stack[#stack] = nil
      owner = top.parent
    end
    for L = i - 1, last - 1 do
      ctx[L] = owner
    end
    i = last + 1
  end
  for _, c in ipairs(stack) do
    c.branches[#c.branches].blast = n - 1
  end
  local seen = {}
  for _, c in ipairs(chains) do
    for _, b in ipairs(c.branches) do
      b.bfirst = b.dlast + 1
    end
    local base = table.concat(c.text, "\31")
    seen[base] = (seen[base] or 0) + 1
    c.sig = base .. "\30" .. seen[base]
  end
  return { chains = chains, roots = roots, ctx = ctx, n = n }
end

function M.classify(tree, lines, inactive)
  for _, c in ipairs(tree.chains) do
    for _, b in ipairs(c.branches) do
      local any, active = false, false
      for L = b.bfirst, b.blast do
        if lines[L + 1]:find("%S") then
          any = true
          if not inactive[L] then
            active = true
            break
          end
        end
      end
      b.state = active and "active" or (any and "inactive" or "empty")
    end
  end
end

function M.cover(tree)
  local cover_chain

  local function cover_items(children)
    local lists, n = {}, 0
    for _, cid in ipairs(children) do
      local l = cover_chain(cid)
      if #l > 0 then
        lists[#lists + 1] = l
        n = math.max(n, #l)
      end
    end
    local res = {}
    for k = 1, n do
      local a = {}
      for _, l in ipairs(lists) do
        for cid, bi in pairs(l[(k - 1) % #l + 1]) do
          a[cid] = bi
        end
      end
      res[k] = a
    end
    return res
  end

  cover_chain = function(cid)
    local res = {}
    for bi, b in ipairs(tree.chains[cid].branches) do
      local sub = cover_items(b.children)
      if b.state == "inactive" or #sub > 0 then
        if #sub == 0 then
          sub = { {} }
        end
        for _, a in ipairs(sub) do
          a[cid] = bi
          res[#res + 1] = a
        end
      end
    end
    return res
  end

  return cover_items(tree.roots)
end

function M.by_sig(tree, assignment)
  local out = {}
  for cid, bi in pairs(assignment) do
    out[tree.chains[cid].sig] = bi
  end
  return out
end

function M.owners(tree, inactive, assignments)
  local owners = {}
  for L in pairs(inactive) do
    local path = {}
    local at = tree.ctx[L]
    while at do
      path[#path + 1] = at
      at = tree.chains[at[1]].parent
    end
    if #path > 0 then
      for k, a in ipairs(assignments) do
        local ok = true
        for _, p in ipairs(path) do
          local want = a[p[1]]
          if want then
            ok = want == p[2]
          else
            ok = tree.chains[p[1]].branches[p[2]].state == "active"
          end
          if not ok then
            break
          end
        end
        if ok then
          owners[L] = k
          break
        end
      end
    end
  end
  return owners
end

function M.rewrite(lines, tree, assign)
  local out = {}
  for i = 1, #lines do
    out[i] = lines[i]
  end
  for _, c in ipairs(tree.chains) do
    local j = assign[c.sig]
    if j then
      for bi, b in ipairs(c.branches) do
        local new
        if bi == 1 then
          new = j == 1 and "#if 1" or "#if 0"
        elseif b.kind ~= "else" then
          new = j == bi and "#elif 1" or "#elif 0"
        end
        if new then
          for L = b.dline, b.dlast do
            out[L + 1] = (L == b.dline and new or "") .. (lines[L + 1]:match("\r$") or "")
          end
        end
      end
    end
  end
  return out
end

function M.rewrite_text(text, assign)
  local lines = vim.split(text, "\n", { plain = true })
  return table.concat(M.rewrite(lines, M.parse(lines), assign), "\n")
end

return M
