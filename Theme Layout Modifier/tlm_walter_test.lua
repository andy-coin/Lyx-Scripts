-- Self-check for tlm_walter.lua (run with a standalone Lua 5.4, not inside REAPER):
--   lua tlm_walter_test.lua "/path/to/rtconfig.txt"
-- Verifies: edits evaluated as overrides == edits written into the file and re-read.
package.path = (arg[0]:match("^(.*)/") or ".") .. "/?.lua;" .. package.path
local W = require "tlm_walter"

local lines = {}
for l in io.lines(arg[1]) do lines[#lines + 1] = l end
local plain, existing = W.extract_managed(lines)
local C = W.compile(plain)
local ctx = { w = 500, h = 80, recarm = 0, trackpanmode = 3, tracknch = 2 }

local lay = C.tcp_layouts[1] or ""
local edits = {
  [""]  = { ["tcp.mute"] = { mode = "offset", dx = 5, dy = -2, dw = 0, dh = 0 },
            ["tcp.solo"] = { mode = "link", link = "tcp.mute", ox = 30, oy = 0, dw = 0, dh = 0 },
            ["tcp.io"] = { hide = true, mode = "offset", dx = 0, dy = 0, dw = 0, dh = 0 },
            ["tcp.recarm"] = { mode = "offset", dx = 0, dy = 0, dw = 0, dh = 0, hh = 100, arm = true } },
  [lay] = { ["tcp.label"] = { mode = "abs", x = 10, y = 3, w = 120, h = 20, att = { 0, 0, 1, 0 } } },
}
edits[""]["master.tcp.mute"] = { mode = "offset", dx = 4, dy = 1, dw = 0, dh = 0 }
local mlay = C.layouts.mcp and C.layouts.mcp[1]
if mlay then
  edits[mlay] = edits[mlay] or {}
  edits[mlay]["mcp.mute"] = { mode = "offset", dx = -3, dy = 7, dw = 0, dh = 0 }
end

edits[""]["trans.play"] = { mode = "offset", dx = 3, dy = 1, dw = 0, dh = 0 }
local tlay = C.layouts.trans and C.layouts.trans[1]
if tlay then
  edits[tlay] = edits[tlay] or {}
  edits[tlay]["trans.stop"] = { mode = "abs", x = 200, y = 4, w = 30, h = 30, att = { 0, 0, 0, 0 }, hw = 600 }
end
ctx.trans_flags = 6

local R1 = W.run(C, ctx, W.compile_overrides(edits))
local composed = W.compose(plain, C, edits)
local plain2, edits2 = W.extract_managed(composed)
local R2 = W.run(W.compile(composed), ctx)

local function same(a, b)
  for k = 1, 8 do if math.abs((a and a[k] or 0) - (b and b[k] or 0)) > 1e-9 then return false end end
  return true
end
for name, recs in pairs(edits) do
  local A = name == "" and R1.G or R1.layouts[name]
  local B = name == "" and R2.G or R2.layouts[name]
  for e in pairs(recs) do
    assert(same(A.vars[e], B.vars[e]), "mismatch " .. name .. " " .. e)
    assert(edits2[name] and edits2[name][e], "record not re-read " .. name .. " " .. e)
  end
end
assert(#plain2 == #plain, "extract_managed did not restore the plain file")
assert(W.rect(R1.G.vars["tcp.io"], 500, 80, 500, 80) == nil, "hide failed")
assert(W.rect(R1.G.vars["tcp.recarm"], 500, 80, 500, 80) == nil, "hide rule h<100 failed")
assert(edits2[""]["tcp.recarm"].hh == 100 and edits2[""]["tcp.recarm"].arm, "rules not re-read")

-- layout ops
local dup = W.compile(W.duplicate_layout(plain, C, lay, "TLM copy"))
assert(dup.last_tcp_block["TLM copy"], "duplicate failed")
local new = W.compile(W.new_layout(plain, C, "TLM new"))
assert(new.last_tcp_block["TLM new"], "new failed")
local del = W.compile(W.delete_layout(plain, C, lay))
assert(not del.last_tcp_block[lay], "delete failed")

local ren = W.compile(W.rename_layout(plain, C, lay, "TLM renamed"))
assert(ren.last_tcp_block["TLM renamed"] and not ren.last_tcp_block[lay], "rename failed")
local mdup = mlay and W.compile(W.duplicate_layout(plain, C, mlay, "TLM mcp copy", "mcp"))
assert(not mlay or mdup.last_block.mcp["TLM mcp copy"], "mcp duplicate failed")
local mnew = W.compile(W.new_layout(plain, C, "TLM mcp new", "mcp"))
assert(mnew.last_block.mcp["TLM mcp new"], "mcp new failed")
print("OK", #C.tcp_layouts .. " tcp / " .. #(C.layouts.mcp or {}) .. " mcp / " .. #(C.layouts["master.tcp"] or {}) .. " master.tcp layouts, tested '" .. lay .. "'" .. (mlay and (" + mcp '" .. mlay .. "'") or ""), next(existing) and "(file had TLM blocks)" or "")
