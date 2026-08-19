local M = {}

-- The disassembly marker does not go in the sign column: that column is a
-- window option, and the panel re-applies its own window options when it
-- switches sections, which makes a sign flash and vanish.  An extmark lives on
-- the buffer, so it stays put no matter what happens to the window.
local ns = vim.api.nvim_create_namespace("dbg_pc")

local function buffer()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "dap-disassembly" then
      return buf
    end
  end
  return nil
end

local function normalise(addr)
  return (addr:lower():gsub("^0x0*", ""))
end

-- Whether the branch under the program counter is about to be taken.  The
-- answer comes from the registers already collected for the register panel, so
-- no extra round trip is needed, and each architecture is only consulted when
-- the target actually exposes the state it needs.
local ALWAYS = {
  b = true,
  bl = true,
  br = true,
  blr = true,
  jmp = true,
  call = true,
  j = true,
  jal = true,
  jr = true,
  jalr = true,
}

local function flags_of(values, name)
  local raw = tostring((values or {})[name] or "")
  local inside = raw:match("%[([^%]]*)%]")
  if not inside then
    return nil
  end
  local set = {}
  for token in inside:gmatch("%a+") do
    set[token:upper()] = true
  end
  return set
end

-- 64-bit values do not survive a double: 0xffff8000803a1870 loses its top
-- nibble.  Everything that must stay exact -- addresses, zero tests, equality --
-- works on a fixed-width hex string instead, and only genuinely small operands
-- become Lua numbers.
local function norm16(value)
  local text = tostring(value or "")
  local digits = text:match("0[xX](%x+)")
  if not digits then
    local n = tonumber(text)
    if not n then
      return nil
    end
    if n < 0 then
      n = n + 2 ^ 64
    end
    digits = ("%x"):format(math.floor(n))
  end
  digits = digits:lower()
  if #digits > 16 then
    digits = digits:sub(-16)
  end
  return string.rep("0", 16 - #digits) .. digits
end

local function to_hex(digits)
  local trimmed = digits:gsub("^0+", "")
  return "0x" .. (trimmed == "" and "0" or trimmed)
end

local function hex_add(digits, delta)
  local hi = tonumber(digits:sub(1, 8), 16)
  local lo = tonumber(digits:sub(9, 16), 16) + delta
  if lo < 0 then
    hi, lo = hi - 1, lo + 0x100000000
  elseif lo >= 0x100000000 then
    hi, lo = hi + 1, lo - 0x100000000
  end
  return ("%08x%08x"):format(hi % 0x100000000, lo)
end

local function is_zero(value)
  local d = norm16(value)
  return d ~= nil and d == string.rep("0", 16)
end

local function ucmp(a, b)
  local x, y = norm16(a), norm16(b)
  if not x or not y then
    return nil
  end
  return x < y and -1 or (x > y and 1 or 0)
end

local function scmp(a, b)
  local x, y = norm16(a), norm16(b)
  if not x or not y then
    return nil
  end
  local nx = tonumber(x:sub(1, 1), 16) >= 8
  local ny = tonumber(y:sub(1, 1), 16) >= 8
  if nx ~= ny then
    return nx and -1 or 1
  end
  return x < y and -1 or (x > y and 1 or 0)
end

local function bit_set(value, index)
  local d = norm16(value)
  if not d or index < 0 or index > 63 then
    return nil
  end
  local nibble = tonumber(d:sub(16 - math.floor(index / 4), 16 - math.floor(index / 4)), 16)
  return nibble ~= nil and (math.floor(nibble / 2 ^ (index % 4)) % 2 == 1)
end

local function as_number(value)
  local digits = tostring(value or ""):match("0[xX](%x+)")
  if digits then
    return tonumber(digits:sub(-15), 16)
  end
  return tonumber(value)
end

local function arm64_taken(mnemonic, operands, values)
  local f = flags_of(values, "cpsr") or flags_of(values, "CPSR")
  local reg = operands:match("^%s*([%w_]+)")
  local n, z, c, v = f and f.N or false, f and f.Z or false, f and f.C or false, f and f.V or false
  local cond = mnemonic:match("^b%.(%a+)$")
  if cond then
    if not f then
      return nil
    end
    local table_ = {
      eq = z,
      ne = not z,
      cs = c,
      hs = c,
      cc = not c,
      lo = not c,
      mi = n,
      pl = not n,
      vs = v,
      vc = not v,
      hi = c and not z,
      ls = not (c and not z),
      ge = n == v,
      lt = n ~= v,
      gt = (not z) and n == v,
      le = not ((not z) and n == v),
      al = true,
      nv = true,
    }
    return table_[cond]
  end
  if mnemonic == "cbz" or mnemonic == "cbnz" then
    if norm16((values or {})[reg]) == nil then
      return nil
    end
    return (mnemonic == "cbz") == is_zero((values or {})[reg])
  end
  if mnemonic == "tbz" or mnemonic == "tbnz" then
    local bit = tonumber(
      operands:match("#0[xX](%x+)") or operands:match("#(%d+)") or "",
      operands:match("#0[xX]%x+") and 16 or 10
    )
    if bit == nil then
      return nil
    end
    local isset = bit_set((values or {})[reg], bit)
    if isset == nil then
      return nil
    end
    return (mnemonic == "tbnz") == isset
  end
  return nil
end

local X86 = {
  je = "Z",
  jz = "Z",
  jne = "!Z",
  jnz = "!Z",
  js = "S",
  jns = "!S",
  jc = "C",
  jb = "C",
  jnae = "C",
  jnc = "!C",
  jae = "!C",
  jnb = "!C",
  jo = "O",
  jno = "!O",
  jp = "P",
  jpe = "P",
  jnp = "!P",
  jpo = "!P",
}

local function x86_taken(mnemonic, _, values)
  local f = flags_of(values, "eflags") or flags_of(values, "rflags")
  if not f then
    return nil
  end
  local zf, sf, cf, of, pf = f.ZF or false, f.SF or false, f.CF or false, f.OF or false, f.PF or false
  local simple = X86[mnemonic]
  if simple then
    local bit = ({ Z = zf, S = sf, C = cf, O = of, P = pf })[simple:gsub("!", "")]
    return simple:sub(1, 1) == "!" and not bit or (simple:sub(1, 1) ~= "!" and bit)
  end
  local compound = {
    ja = (not cf) and not zf,
    jnbe = (not cf) and not zf,
    jbe = cf or zf,
    jna = cf or zf,
    jg = (not zf) and sf == of,
    jnle = (not zf) and sf == of,
    jge = sf == of,
    jnl = sf == of,
    jl = sf ~= of,
    jnge = sf ~= of,
    jle = zf or sf ~= of,
    jng = zf or sf ~= of,
  }
  return compound[mnemonic]
end

local function riscv_taken(mnemonic, operands, values)
  local a, b = operands:match("^%s*([%w_]+)%s*,%s*([%w_]+)")
  if not a then
    return nil
  end
  local function value_of(name)
    if name == "zero" or name == "x0" then
      return "0x0"
    end
    local v = (values or {})[name]
    return v ~= nil and norm16(v) or nil
  end
  local zero_forms = { beqz = "beq", bnez = "bne", bltz = "blt", bgez = "bge" }
  if zero_forms[mnemonic] then
    local v = value_of(a)
    if v == nil then
      return nil
    end
    local m = zero_forms[mnemonic]
    if m == "beq" then
      return is_zero(v)
    elseif m == "bne" then
      return not is_zero(v)
    end
    local sign = scmp(v, "0x0")
    return m == "blt" and sign < 0 or (m == "bge" and sign >= 0)
  end
  local x, y = value_of(a), value_of(b)
  if x == nil or y == nil then
    return nil
  end
  local u, si = ucmp(x, y), scmp(x, y)
  if u == nil or si == nil then
    return nil
  end
  local ops = {
    beq = u == 0,
    bne = u ~= 0,
    blt = si < 0,
    bge = si >= 0,
    bltu = u < 0,
    bgeu = u >= 0,
  }
  return ops[mnemonic]
end

-- An indirect branch has no address in the text, but standing on it the
-- register that decides where it goes is already known, so the destination can
-- be read straight out of the stopped state.
local function indirect_target(mnemonic, operands, values, arch)
  values = values or {}
  -- returns the 16-digit form so the address survives intact
  local function reg(name)
    if not name then
      return nil
    end
    name = name:gsub("^[%*%%]+", "")
    return norm16(values[name])
  end
  -- att prints `*%rax`, intel prints `rax`; both must reach the register name
  local first = operands:match("^%s*([%%%*]*[%w_]+)")

  if arch == "aarch64" then
    if mnemonic == "ret" then
      return reg(first) or reg("x30") or reg("lr")
    end
    if mnemonic == "br" or mnemonic == "blr" then
      return reg(first)
    end
    return nil
  end

  if arch == "riscv64" then
    if mnemonic == "ret" then
      return reg("ra") or reg("x1")
    end
    if mnemonic == "jr" then
      return reg(first)
    end
    if mnemonic == "jalr" then
      -- jalr rd, rs, imm  |  jalr rs  |  jalr rd, imm(rs)
      local base, offset = operands:match("(-?%d+)%s*%(%s*([%w_]+)%s*%)")
      if base and offset then
        local v = reg(offset)
        return v and hex_add(v, tonumber(base)) or nil
      end
      local parts = {}
      for token in operands:gmatch("[^,%s]+") do
        parts[#parts + 1] = token
      end
      local rs = parts[2] or parts[1]
      local imm = tonumber(parts[3] or "0") or 0
      local v = reg(rs)
      return v and hex_add(v, imm) or nil
    end
    return nil
  end

  if arch == "x86_64" then
    -- `jmp *%rax` (att) or `jmp rax` (intel); a memory operand needs a read,
    -- which is not done here, so those stay unresolved rather than guessed.
    if (mnemonic == "jmp" or mnemonic == "call") and not operands:find("[%[%]]") then
      return reg(first)
    end
    return nil
  end

  return nil
end

-- Which instruction set this is, decided by the registers the target actually
-- exposes rather than by a configured architecture name.  Each ISA then gets
-- its own evaluator: the mnemonics barely overlap, but the state they consult
-- does not overlap at all, and mixing them would give confident wrong answers.
local function detect_arch(values)
  values = values or {}
  if values.cpsr ~= nil or values.CPSR ~= nil then
    return "aarch64"
  end
  if values.eflags ~= nil or values.rflags ~= nil then
    return "x86_64"
  end
  if values.satp ~= nil or values.a0 ~= nil or values.t0 ~= nil then
    return "riscv64"
  end
  return nil
end

local EVALUATE = {
  aarch64 = arm64_taken,
  x86_64 = x86_taken,
  riscv64 = riscv_taken,
}

-- Returns target address string, taken (true/false/nil when undecidable).
function M.branch_at(line, values)
  local body = line:gsub("^%s*0[xX]%x+:%s*", "")
  -- The instruction-bytes column is a lone hex blob before the mnemonic, but a
  -- mnemonic can be valid hex too: stripping "%x+%s+" ate the `b` in
  -- "b 0xffff..." and left the target as the mnemonic.  Only strip an
  -- even-length hex run that is actually followed by something starting with a
  -- letter, and only when a byte column is present at all.
  local head, rest = body:match("^(%S+)%s+(.*)$")
  if head and rest and #head >= 2 and #head % 2 == 0 and head:match("^%x+$") and rest:match("^%a") then
    body = rest
  end
  local mnemonic, operands = body:match("^(%S+)%s*(.*)$")
  if not mnemonic then
    return nil
  end
  mnemonic = mnemonic:lower()
  local target = nil
  for addr in operands:gmatch("0[xX]%x+") do
    target = addr
  end
  local arch = detect_arch(values)
  if ALWAYS[mnemonic] or mnemonic == "ret" then
    if not target then
      local resolved = indirect_target(mnemonic, operands, values, arch)
      if resolved then
        target = to_hex(resolved)
      end
    end
    return target, true, arch
  end
  if not target then
    return nil
  end
  local evaluate = arch and EVALUATE[arch]
  -- `x and f() or nil` would turn a legitimate `false` into `nil`, and "will
  -- not branch" is exactly the answer this feature exists to show.
  local taken = nil
  if evaluate then
    taken = evaluate(mnemonic, operands, values)
  end
  if taken == nil and not mnemonic:match("^[bj]") then
    return nil
  end
  return target, taken, arch
end

function M.clear()
  local buf = buffer()
  if buf then
    pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
  end
end

function M.mark(session)
  local buf = buffer()
  if not buf then
    return
  end
  pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
  session = session or require("dap").session()
  local frame = session and session.current_frame
  local pc = frame and frame.instructionPointerReference
  if not pc then
    return
  end
  local want = normalise(pc)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    local addr = line:match("(0[xX]%x+)")
    if addr and normalise(addr) == want then
      -- Background only, so the instruction's own colours survive; a text
      -- marker next to it just competes with them.
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, i - 1, 0, {
        line_hl_group = "DbgPcLine",
        priority = 200,
      })
      local win = vim.fn.bufwinid(buf)
      if win ~= -1 then
        pcall(vim.api.nvim_win_set_cursor, win, { i, 0 })
      end
      M.draw_branch(buf, lines, i)
      return
    end
  end
end

-- A connector from the branch to its destination.  It cannot live in the sign
-- column: dap-view sets `statuscolumn = ""` on its panel window
-- (views/options.lua:14), which stops signs being drawn at all.  Instead every
-- row of the buffer gets the same two-cell inline prefix, so the listing shifts
-- as a whole and stays aligned, and nothing is drawn when the program counter
-- is not on a branch.
function M.draw_branch(buf, lines, pc_row)
  local ok, registers = pcall(require, "dbg.registers")
  local values = ok and registers.values() or {}
  local target, taken = M.branch_at(lines[pc_row] or "", values)
  if not target then
    return
  end
  -- Only a branch that is actually about to be taken gets a connector.  One
  -- that will fall through draws nothing: the absence is the answer.  When the
  -- condition cannot be decided the connector is drawn dim, so an unknown is
  -- never mistaken for a certainty.
  if taken == false then
    return
  end
  local group = taken == true and "DbgBranchTaken" or "DbgBranchUnknown"

  local want = normalise(target)
  local target_row = nil
  for i, line in ipairs(lines) do
    local addr = line:match("(0[xX]%x+)")
    if addr and normalise(addr) == want then
      target_row = i
      break
    end
  end

  local glyph = {}
  if not target_row then
    local here = as_number((lines[pc_row] or ""):match("(0[xX]%x+)"))
    local there = as_number(target)
    glyph[pc_row] = (here and there and there < here) and "\u{25b2} " or "\u{25bc} "
  elseif target_row == pc_row then
    glyph[pc_row] = "\u{21bb} "
  else
    local from, to = math.min(pc_row, target_row), math.max(pc_row, target_row)
    for row = from + 1, to - 1 do
      glyph[row] = "\u{2502} "
    end
    if target_row > pc_row then
      glyph[pc_row] = "\u{256d} "
      glyph[target_row] = "\u{2570}\u{25b6}"
    else
      glyph[target_row] = "\u{256d}\u{25b6}"
      glyph[pc_row] = "\u{2570} "
    end
  end

  for row = 1, #lines do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, row - 1, 0, {
      virt_text = { { glyph[row] or "  ", glyph[row] and group or "DbgMuted" } },
      virt_text_pos = "inline",
      right_gravity = false,
      priority = 190,
    })
  end
end

function M.setup()
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    pattern = "*",
    callback = function(ev)
      if vim.bo[ev.buf].filetype ~= "dap-disassembly" then
        return
      end
      vim.schedule(function()
        M.mark()
      end)
    end,
    desc = "Mark the instruction the program counter is on whenever the disassembly is shown",
  })
end

return M
