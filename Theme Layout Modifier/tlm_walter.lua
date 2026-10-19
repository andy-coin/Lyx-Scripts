-- tlm_walter.lua
-- WALTER (rtconfig.txt) engine for Theme Layout Modifier.
-- Pure Lua (no reaper.* calls) so it can be tested outside REAPER.
--
--   compile(lines)            -> C   (macros/defs expanded, flat statement list, layout blocks)
--   run(C, ctx, overrides)    -> R   (every variable/element evaluated for one preview context)
--   rect(v, R_layout, W, H)   -> l,t,r,b in panel pixels (edge attachment applied)
--   managed blocks: our edits are written as plain WALTER "set" lines between TLM markers,
--   so the preview is literally "the same file REAPER will read".

local M = {}

local IDX = { x = 0, y = 1, w = 2, h = 3, ls = 4, ts = 5, rs = 6, bs = 7 }
for i = 0, 7 do IDX[tostring(i)] = i end
M.IDX = IDX

----------------------------------------------------------------------------------------------------
-- Text -> logical lines
----------------------------------------------------------------------------------------------------
local function strip_comment(s)
  if not s:find("[;'\"]") then return s end
  local q
  for i = 1, #s do
    local c = s:sub(i, i)
    if q then
      if c == q then q = nil end
    elseif c == "'" or c == '"' then
      -- only treat as a quote when it opens a token (avoids "don't" in odd places)
      local prev = i > 1 and s:sub(i - 1, i - 1) or " "
      if prev:match("%s") then q = c end
    elseif c == ";" then
      return s:sub(1, i - 1)
    end
  end
  return s
end

function M.logical_lines(lines)
  local out, i, n = {}, 1, #lines
  while i <= n do
    local first = i
    local s = strip_comment(lines[i])
    while s:find("\\%s*$") and i < n do
      s = s:gsub("\\%s*$", " ")
      i = i + 1
      s = s .. strip_comment(lines[i])
    end
    if s:find("%S") then out[#out + 1] = { text = s, line = first, last = i } end
    i = i + 1
  end
  return out
end

local function tokenize(s)
  local t, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif c == "'" or c == '"' then
      local j = s:find(c, i + 1, true) or (n + 1)
      t[#t + 1] = s:sub(i + 1, j - 1)
      i = j + 1
    elseif c == "[" or c == "]" then
      t[#t + 1] = c
      i = i + 1
    else
      local j = s:find("[%s%[%]]", i) or (n + 1)
      t[#t + 1] = s:sub(i, j - 1)
      i = j
    end
  end
  return t
end
M.tokenize = tokenize

-- identifier-boundary replacement (used by def and macro parameters)
local function subst(s, map)
  return (s:gsub("[%w_%.]+", map))
end

local function expand_defs(s, defs)
  for _ = 1, 10 do
    local s2 = subst(s, defs)
    if s2 == s then break end
    s = s2
  end
  return s
end

----------------------------------------------------------------------------------------------------
-- Compile
----------------------------------------------------------------------------------------------------
local function head_of(text) return (text:match("^%s*(%S+)") or ""):lower() end

-- UI section an element/pattern belongs to: "tcp", "mcp", "master.tcp", "master.mcp", "envcp", "trans" ...
function M.sec_of(name)
  local m = name:match("^master%.(%a+)%.")
  if m then return "master." .. m end
  return name:match("^(%a+)%.")
end
local sec_of = M.sec_of

function M.compile(lines)
  local LL = M.logical_lines(lines)
  local C = {
    stmts = {}, blocks = {}, params = {}, param_order = {}, cfg = {}, customs = {},
    layouts = {}, last_block = {}, nlines = #lines, warnings = {},
  }
  local defs, macros = {}, {}
  local cur_block

  local function emit(st)
    st.block = cur_block
    C.stmts[#C.stmts + 1] = st
  end

  local function close_block(stop)
    if not cur_block then return end
    cur_block.stop = stop
    emit({ cmd = "endlayout" })
    cur_block = nil
  end

  local walk
  walk = function(list, line_override, depth)
    if depth > 40 then
      C.warnings[#C.warnings + 1] = "macro recursion too deep"
      return
    end
    local i = 1
    while i <= #list do
      local rec = list[i]
      local text = rec.text
      local ln = line_override or rec.line
      local h = head_of(text)

      if h == "macro" then
        local tk = tokenize(text)
        -- no nesting: a new "macro" line implicitly ends the current one (themes rely on this)
        local body, j = {}, i + 1
        while j <= #list do
          local h2 = head_of(list[j].text)
          if h2 == "macro" or h2 == "endmacro" then break end
          body[#body + 1] = list[j]
          j = j + 1
        end
        if tk[2] then macros[tk[2]] = { params = { table.unpack(tk, 3) }, body = body } end
        i = (list[j] and head_of(list[j].text) == "macro") and j or j + 1

      elseif h == "def" then
        local name, val = text:match("^%s*%S+%s+(%S+)%s*(.-)%s*$")
        if name then defs[name] = val end
        i = i + 1

      elseif h == "layout" then
        close_block(ln - 1)
        local tk = tokenize(expand_defs(text, defs))
        cur_block = { name = tk[2] or "", imgdir = tk[3], start = ln, secs = {}, macro = line_override ~= nil }
        C.blocks[#C.blocks + 1] = cur_block
        emit({ cmd = "layout", name = cur_block.name, imgdir = tk[3] })
        i = i + 1

      elseif h == "endlayout" then
        close_block(ln)
        i = i + 1

      else
        local s = expand_defs(text, defs)
        local tk = tokenize(s)
        local cmd = tk[1] or ""
        local lc = cmd:lower()
        local mac = macros[cmd]
        if mac then
          -- macro args: bracket groups count as one argument
          local args, k = {}, 2
          while k <= #tk do
            if tk[k] == "[" then
              local g = {}
              while k <= #tk and tk[k] ~= "]" do g[#g + 1] = tk[k]; k = k + 1 end
              g[#g + 1] = "]"
              args[#args + 1] = table.concat(g, " ")
            else
              args[#args + 1] = tk[k]
            end
            k = k + 1
          end
          local map = {}
          for p, name in ipairs(mac.params) do map[name] = args[p] end -- missing arg: name stays (themes rely on it)
          local body = {}
          for _, b in ipairs(mac.body) do
            body[#body + 1] = { text = subst(b.text, map):gsub("##", ""), line = b.line }
          end
          walk(body, ln, depth + 1)
        elseif lc == "set" and tk[2] then
          local toks = {}
          for k = 3, #tk do
            if tk[k]:sub(1, 2) == "--" then break end -- "--" disables the rest
            toks[#toks + 1] = tk[k]
          end
          emit({ cmd = "set", target = tk[2], toks = toks, line = ln })
          local sc = cur_block and sec_of(tk[2])
          if sc then cur_block.secs[sc] = true end
        elseif (lc == "clear" or lc == "reset") and tk[2] then
          emit({ cmd = "clear", pat = tk[2] })
          local sc = cur_block and sec_of(tk[2])
          if sc then cur_block.secs[sc] = true end
        elseif lc == "front" then
          emit({ cmd = "front", list = { table.unpack(tk, 2) } })
        elseif lc == "define_parameter" and tk[2] then
          if not C.params[tk[2]] then C.param_order[#C.param_order + 1] = tk[2] end
          C.params[tk[2]] = {
            desc = tk[3] or tk[2], def = tonumber(tk[4]) or 0,
            min = tonumber(tk[5]) or 0, max = tonumber(tk[6]) or 1,
          }
        elseif lc == "custom" and tk[2] then
          C.customs[tk[2]] = { label = tk[3], command = tk[4], desc = tk[5], image = tk[6] }
        elseif not cur_block and cmd:match("^[%a_]") then
          C.cfg[cmd] = { table.unpack(tk, 2) } -- theme-wide settings (global_scale, tcp_heights, ...)
        end
        i = i + 1
      end
    end
  end

  walk(LL, nil, 0)
  close_block(#lines)

  -- per section: which layouts exist, and where each one's last block for that section ends (= where our edits go)
  for _, b in ipairs(C.blocks) do
    b.tcp = b.secs.tcp
    for sc in pairs(b.secs) do
      C.layouts[sc] = C.layouts[sc] or {}
      C.last_block[sc] = C.last_block[sc] or {}
      if not C.last_block[sc][b.name] then C.layouts[sc][#C.layouts[sc] + 1] = b.name end
      C.last_block[sc][b.name] = b
    end
  end
  C.tcp_layouts = C.layouts.tcp or {}
  C.last_tcp_block = C.last_block.tcp or {}
  return C
end

----------------------------------------------------------------------------------------------------
-- Evaluate
----------------------------------------------------------------------------------------------------
local function fill(x) return { x, x, x, x, x, x, x, x } end
local function copy(v) return v and { v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8] } or nil end
M.copy = copy

local scalar
scalar = function(tok, E, idx)
  local n = tonumber(tok)
  if n then return n end
  if tok:sub(1, 1) == "-" and #tok > 1 then return -scalar(tok:sub(2), E, idx) end
  local base, sub = tok:match("^(.-){(%w+)}$")
  if base then
    local v, k = E.vars[base], IDX[sub]
    if v and k then return v[k + 1] or 0 end
    return E.ctx[base] or 0
  end
  local c = E.ctx[tok]
  if c then return c end
  local v = E.vars[tok]
  if v then return v[(idx or 0) + 1] or 0 end
  return 0
end

local function is_cond(tok)
  return tok:find("^[%?!]") or tok:find("[<>=&]")
end

local function cond(tok, E)
  local c1 = tok:sub(1, 1)
  if c1 == "?" then return scalar(tok:sub(2), E) ~= 0 end
  if c1 == "!" and not tok:find("=", 2, true) then return scalar(tok:sub(2), E) == 0 end
  local p = tok:find("[<>=!&]", 2)
  if not p then return scalar(tok, E) ~= 0 end
  local op, q = tok:sub(p, p), p + 1
  if tok:sub(p + 1, p + 1) == "=" then op = op .. "="; q = p + 2 end
  local a, b = scalar(tok:sub(1, p - 1), E), scalar(tok:sub(q), E)
  if op == "<" then return a < b
  elseif op == ">" then return a > b
  elseif op == "<=" then return a <= b
  elseif op == ">=" then return a >= b
  elseif op == "==" or op == "=" then return a == b
  elseif op == "!=" then return a ~= b
  elseif op == "&" then return (math.floor(a) & math.floor(b)) ~= 0
  end
  return false
end

local expr
expr = function(t, i, cur, E)
  local tok = t[i]
  if tok == nil then return copy(cur) or fill(0), i end

  if tok == "[" then
    local v, j, k = fill(0), i + 1, 1
    while t[j] and t[j] ~= "]" do
      if k <= 8 then
        local it = t[j]
        if it == "." then v[k] = cur and cur[k] or 0 else v[k] = scalar(it, E, k - 1) end
      end
      k = k + 1
      j = j + 1
    end
    return v, j + 1
  end

  if tok == "." then return copy(cur) or fill(0), i + 1 end

  local op, a1, a2
  if tok == "+" or tok == "-" or tok == "*" or tok == "/" then
    op = tok
  else
    local o, x1, x2 = tok:match("^([%+%*]):([^:]+):([^:]+)$")
    if o then op = o .. ":"; a1 = scalar(x1, E); a2 = scalar(x2, E) end
  end
  if op then
    local A, B
    A, i = expr(t, i + 1, cur, E)
    if t[i] == nil then B = copy(cur) or fill(0) else B, i = expr(t, i, cur, E) end
    local R = {}
    for k = 1, 8 do
      local a, b = A[k], B[k]
      if op == "+" then R[k] = a + b
      elseif op == "-" then R[k] = a - b
      elseif op == "*" then R[k] = a * b
      elseif op == "/" then R[k] = (b ~= 0) and a / b or 0
      elseif op == "+:" then R[k] = a1 * a + a2 * b
      else R[k] = (a + a1) * (b + a2) end
    end
    return R, i
  end

  if is_cond(tok) then
    local c = cond(tok, E)
    local A, B
    A, i = expr(t, i + 1, cur, E)
    if t[i] == nil then B = copy(cur) or fill(0) else B, i = expr(t, i, cur, E) end
    return c and A or B, i
  end

  local base, comp = tok:match("^(.+)@(%w+)$")
  if base and IDX[comp] then
    local k = IDX[comp]
    local v = fill(0)
    v[k + 1] = scalar(base, E, k)
    return v, i + 1
  end
  local vv = E.vars[tok]
  if vv then return copy(vv), i + 1 end
  return fill(scalar(tok, E, 0)), i + 1
end

function M.eval_tokens(toks, cur, vars, ctx)
  return (expr(toks, 1, cur, { vars = vars, ctx = ctx }))
end

local function new_state(name, imgdir)
  return { name = name, imgdir = imgdir, vars = {}, ver = {}, own = {}, front = {}, n = 0 }
end

-- ctx: scalar table (w, h, recarm, ...). overrides[layout_name] = compiled statements ("" = default)
function M.run(C, ctx, overrides)
  overrides = overrides or {}
  local G = new_state("", nil)
  local layouts = {}
  local S = G
  local E = { vars = G.vars, ctx = ctx }

  local function exec(st)
    if st.cmd == "set" then
      E.vars = S.vars
      S.vars[st.target] = (expr(st.toks, 1, S.vars[st.target], E))
      G.n = G.n + 1
      S.ver[st.target] = G.n
      S.own[st.target] = true
    elseif st.cmd == "clear" then
      local pat = st.pat
      if pat:sub(-1) == "*" then
        local pre = pat:sub(1, -2)
        for k in pairs(S.vars) do
          if k:sub(1, #pre) == pre then S.vars[k] = nil end
        end
      else
        S.vars[pat] = nil
      end
    elseif st.cmd == "front" then
      for _, e in ipairs(st.list) do
        for k = #S.front, 1, -1 do if S.front[k] == e then table.remove(S.front, k) end end
        S.front[#S.front + 1] = e
      end
    end
  end

  local function exec_overrides(name)
    for _, st in ipairs(overrides[name] or {}) do exec(st) end
  end

  for _, st in ipairs(C.stmts) do
    if st.cmd == "layout" then
      local L = layouts[st.name]
      if not L then
        L = new_state(st.name, st.imgdir)
        for k, v in pairs(G.vars) do L.vars[k] = v end
        for k, v in ipairs(G.front) do L.front[k] = v end
        L.sync = G.n
        layouts[st.name] = L
      else
        -- later block of the same layout: pick up globals set since, unless the layout owns them
        for k, v in pairs(G.vars) do
          if (G.ver[k] or 0) > L.sync and not L.own[k] then L.vars[k] = v end
        end
        L.sync = G.n
        L.imgdir = L.imgdir or st.imgdir
      end
      S = L
    elseif st.cmd == "endlayout" then
      local b = st.block
      if b and overrides[b.name] then
        for _, o in ipairs(overrides[b.name]) do
          local lb = C.last_block[o.sec]
          if lb and lb[b.name] == b then exec(o) end
        end
      end
      S = G
    else
      exec(st)
    end
  end
  S = G
  exec_overrides("")
  return { G = G, layouts = layouts }
end

-- Final rect of an element for panel size W x H (edge attachment relative to tcp.size baseline)
function M.rect(v, base_w, base_h, W, H)
  if not v then return nil end
  local dx, dy = W - base_w, H - base_h
  local l = v[1] + v[5] * dx
  local t = v[2] + v[6] * dy
  local r = v[1] + v[3] + v[7] * dx
  local b = v[2] + v[4] + v[8] * dy
  l, t, r, b = math.floor(l + 0.5), math.floor(t + 0.5), math.floor(r + 0.5), math.floor(b + 0.5)
  if r <= l or b <= t then return nil end
  return l, t, r, b
end

----------------------------------------------------------------------------------------------------
-- Edits <-> WALTER lines (managed blocks)
----------------------------------------------------------------------------------------------------
local BEGIN, END = ";>>> TLM begin", ";<<< TLM end"
M.MARK_BEGIN = BEGIN

local function g(x) return string.format("%g", x or 0) end
local function att_str(a) return g(a[1]) .. " " .. g(a[2]) .. " " .. g(a[3]) .. " " .. g(a[4]) end

-- rec fields: hide, mode ("offset"|"abs"|"link"), dx dy dw dh, x y w h, att{ls,ts,rs,bs}, link, ox oy, lsize
-- hide rules (stacked on top of the theme's own logic): hh/hw = hide when panel h/w below; arm/sel = only when rec-armed/selected
local function main_expr(e, r)
  if r.mode == "abs" then
    return string.format("[%s %s %s %s %s]", g(r.x), g(r.y), g(r.w), g(r.h), att_str(r.att or { 0, 0, 0, 0 }))
  elseif r.mode == "link" and r.link then
    local A = r.link
    local base = string.format("[%s{x} %s{y} 0 0 %s{ls} %s{ts} %s{ls} %s{ts}]", A, A, A, A, A, A)
    if r.lsize then -- element had no theme position: absolute size
      return string.format("+ %s [%s %s %s %s]", base, g(r.ox), g(r.oy), g(r.w), g(r.h))
    end
    return string.format("%s{w}==0 . + + %s [%s %s %s %s] [0 0 . .]", e, base, g(r.ox), g(r.oy), g(r.dw), g(r.dh))
  end
  local d = string.format("[%s %s %s %s]", g(r.dx), g(r.dy), g(r.dw), g(r.dh))
  if r.att then return string.format("%s{w}==0 . + %s [. . . . %s]", e, d, att_str(r.att)) end
  if (r.dx or 0) == 0 and (r.dy or 0) == 0 and (r.dw or 0) == 0 and (r.dh or 0) == 0 then return "." end
  return string.format("%s{w}==0 . + %s .", e, d)
end

function M.has_rules(r) return r.hh or r.hw or r.arm or r.sel end

function M.rec_expr(e, r)
  if r.hide then return "[0]" end
  local pre = {}
  if r.hh then pre[#pre + 1] = "h<" .. g(r.hh) .. " [0]" end
  if r.hw then pre[#pre + 1] = "w<" .. g(r.hw) .. " [0]" end
  if r.arm then pre[#pre + 1] = "!recarm [0]" end
  if r.sel then pre[#pre + 1] = "!track_selected [0]" end
  pre[#pre + 1] = main_expr(e, r)
  return table.concat(pre, " ")
end

local REC_NUM = { "dx", "dy", "dw", "dh", "x", "y", "w", "h", "ox", "oy", "hh", "hw" }

local function rec_comment(e, r)
  local p = { ";TLM e=" .. e, "m=" .. (r.mode or "offset") }
  for _, k in ipairs(REC_NUM) do if r[k] then p[#p + 1] = k .. "=" .. g(r[k]) end end
  if r.hide then p[#p + 1] = "hide=1" end
  if r.lsize then p[#p + 1] = "lsize=1" end
  if r.arm then p[#p + 1] = "arm=1" end
  if r.sel then p[#p + 1] = "sel=1" end
  if r.link then p[#p + 1] = "link=" .. r.link end
  if r.att then p[#p + 1] = "a=" .. g(r.att[1]) .. "," .. g(r.att[2]) .. "," .. g(r.att[3]) .. "," .. g(r.att[4]) end
  return table.concat(p, " ")
end

local function parse_rec_comment(s)
  local c = s:match(";TLM (.*)$")
  if not c then return nil end
  local r, e = {}, nil
  for k, v in c:gmatch("(%w+)=(%S+)") do
    if k == "e" then e = v
    elseif k == "m" then r.mode = v
    elseif k == "hide" then r.hide = true
    elseif k == "lsize" then r.lsize = true
    elseif k == "arm" then r.arm = true
    elseif k == "sel" then r.sel = true
    elseif k == "link" then r.link = v
    elseif k == "a" then
      local a = {}
      for x in v:gmatch("[^,]+") do a[#a + 1] = tonumber(x) or 0 end
      r.att = a
    else r[k] = tonumber(v) end
  end
  return e, r
end

-- link targets must be written before the linked element
local function ordered(recs)
  local names = {}
  for e in pairs(recs) do names[#names + 1] = e end
  table.sort(names)
  local out, done = {}, {}
  for _ = 1, #names + 1 do
    for _, e in ipairs(names) do
      local r = recs[e]
      if not done[e] then
        local dep = (not r.hide and r.mode == "link") and r.link or nil
        if not dep or done[dep] or not recs[dep] then out[#out + 1] = e; done[e] = true end
      end
    end
  end
  for _, e in ipairs(names) do if not done[e] then out[#out + 1] = e end end -- cycles
  return out
end

function M.rec_lines(recs, indent)
  local out = {}
  for _, e in ipairs(ordered(recs)) do
    out[#out + 1] = indent .. "set " .. e .. " " .. M.rec_expr(e, recs[e]) .. " " .. rec_comment(e, recs[e])
  end
  return out
end

-- compile override lines into statements run() can inject
function M.compile_overrides(edits)
  local ov = {}
  for name, recs in pairs(edits) do
    local st = {}
    for _, line in ipairs(M.rec_lines(recs, "")) do
      local tk = tokenize(strip_comment(line))
      st[#st + 1] = { cmd = "set", target = tk[2], toks = { table.unpack(tk, 3) }, sec = sec_of(tk[2]) }
    end
    ov[name] = st
  end
  return ov
end

-- remove our managed blocks from the file, returning plain lines + edits table
function M.extract_managed(lines)
  local out, edits, i = {}, {}, 1
  local cur_layout = ""
  while i <= #lines do
    local s = lines[i]
    local h = head_of(s)
    if h == "layout" then
      local tk = tokenize(strip_comment(s))
      cur_layout = tk[2] or ""
    elseif h == "endlayout" then
      cur_layout = ""
    end
    if s:find(BEGIN, 1, true) then
      local name = s:match('layout="(.-)"$') or cur_layout
      edits[name] = edits[name] or {}
      i = i + 1
      while i <= #lines and not lines[i]:find(END, 1, true) do
        local e, r = parse_rec_comment(lines[i])
        if e then edits[name][e] = r end
        i = i + 1
      end
    else
      out[#out + 1] = s
    end
    i = i + 1
  end
  return out, edits
end

local function quote(n) return n:find('"') and ("'" .. n .. "'") or ('"' .. n .. '"') end

-- a layout's edits are written as their own "Layout X ... EndLayout" block right after the layout's
-- last block for that section (blocks with the same name continue the same layout). This also works
-- for themes whose macros close the layout block themselves.
local function block_lines(name, recs, indent)
  local t = { indent .. BEGIN .. ' (generated by Lyx Theme Layout Modifier) layout="' .. name .. '"' }
  local inner = indent
  if name ~= "" then
    t[#t + 1] = indent .. "Layout " .. quote(name)
    inner = indent .. "\t"
  end
  for _, l in ipairs(M.rec_lines(recs, inner)) do t[#t + 1] = l end
  if name ~= "" then t[#t + 1] = indent .. "EndLayout" end
  t[#t + 1] = indent .. END
  return t
end

-- plain lines + edits -> final file lines
function M.compose(lines, C, edits)
  local after, tail = {}, nil
  for name, recs in pairs(edits) do
    if next(recs) then
      if name == "" then
        tail = recs
      else
        local by_sec = {}
        for e, r in pairs(recs) do
          local sc = sec_of(e)
          if sc then by_sec[sc] = by_sec[sc] or {}; by_sec[sc][e] = r end
        end
        for sc, part in pairs(by_sec) do
          local b = C.last_block[sc] and C.last_block[sc][name]
          if b and b.stop and not b.macro then
            local ind = (lines[b.start] or ""):match("^(%s*)")
            local slot = after[b.stop] or {}
            for _, l in ipairs(block_lines(name, part, ind)) do slot[#slot + 1] = l end
            after[b.stop] = slot
          end
        end
      end
    end
  end
  local out = {}
  for i, s in ipairs(lines) do
    out[#out + 1] = s
    if after[i] then for _, l in ipairs(after[i]) do out[#out + 1] = l end end
  end
  if tail then
    for _, l in ipairs(block_lines("", tail, "")) do out[#out + 1] = l end
  end
  return out
end

----------------------------------------------------------------------------------------------------
-- Layout operations on plain lines
----------------------------------------------------------------------------------------------------

local function sec_blocks(C, name, sec)
  local t = {}
  for _, b in ipairs(C.blocks) do if b.secs[sec or "tcp"] and b.name == name then t[#t + 1] = b end end
  return t
end

function M.can_edit_blocks(C, name, sec)
  local bl = sec_blocks(C, name, sec)
  if #bl == 0 then return false end
  for _, b in ipairs(bl) do if b.macro or not b.stop then return false end end
  return true
end

function M.duplicate_layout(lines, C, src, dst, sec)
  local out = { table.unpack(lines) }
  local bl = sec_blocks(C, src, sec)
  for k = #bl, 1, -1 do
    local b = bl[k]
    local chunk = {}
    for i = b.start, b.stop do chunk[#chunk + 1] = lines[i] end
    local ind = chunk[1]:match("^(%s*)")
    chunk[1] = ind .. "Layout " .. quote(dst) .. (b.imgdir and (" " .. quote(b.imgdir)) or "")
    for j = #chunk, 1, -1 do table.insert(out, b.stop + 1, chunk[j]) end
  end
  return out
end

function M.delete_layout(lines, C, name, sec)
  local out = { table.unpack(lines) }
  local bl = sec_blocks(C, name, sec)
  for k = #bl, 1, -1 do
    for i = bl[k].stop, bl[k].start, -1 do table.remove(out, i) end
  end
  return out
end

function M.rename_layout(lines, C, old, new, sec)
  local out = { table.unpack(lines) }
  for _, b in ipairs(sec_blocks(C, old, sec)) do
    local ind = out[b.start]:match("^(%s*)")
    out[b.start] = ind .. "Layout " .. quote(new) .. (b.imgdir and (" " .. quote(b.imgdir)) or "")
  end
  return out
end

function M.new_layout(lines, C, name, sec)
  sec = sec or "tcp"
  local out = { table.unpack(lines) }
  local pos = #out
  local last
  for _, b in ipairs(C.blocks) do if b.secs[sec] and b.stop and not b.macro then last = b end end
  if last then pos = last.stop end
  local chunk = { "", "Layout " .. quote(name), "\tset " .. sec .. ".size .", "EndLayout" }
  for j = #chunk, 1, -1 do table.insert(out, pos + 1, chunk[j]) end
  return out
end

return M
