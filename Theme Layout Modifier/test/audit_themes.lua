-- Theme audit (standalone Lua 5.4): lua test/audit_themes.lua <rtconfig.txt>
-- Compiles + runs a theme at 5 sizes x 2 states; reports errors, NaN/inf, ids never set (subscripts like x/ls and
-- macro-built names show up as false positives), and ms per evaluation.
package.path = (arg[0]:match("^(.*)/test/") or ".") .. "/?.lua;" .. package.path
local W = require "tlm_walter"
local path = arg[1]
local lines = {}
for l in io.lines(path) do lines[#lines + 1] = l end
local t0 = os.clock()
local ok, plain, edits = pcall(W.extract_managed, lines)
if not ok then print("EXTRACT ERROR", plain) return end
local ok2, C = pcall(W.compile, plain)
if not ok2 then print("COMPILE ERROR", C) return end
local KNOWN = {}
for k in ([[w h folderstate folderdepth maxfolderdepth recarm tcp_iconsize mcp_iconsize mcp_maxfolderdepth mcp_wantextmix
 tracknch trackpanmode tcp_fxparms tcp_fxembed mcp_fxembed reaper_version os_type trackcolor_valid trackcolor_r trackcolor_g
 trackcolor_b track_selected trackidx ntracks mixer_visible tcp_sends_enabled tcp_fxlist_enabled send_cnt fx_parm_cnt fx_cnt
 recfx_cnt trackfixedlanes trackpinned tcp_hidden_overridden trans_flags trans_center trans_docked]]):gmatch("%S+") do KNOWN[k] = true end
-- identifiers used in expressions that are never set / defined / known
local setv = {}
for _, st in ipairs(C.stmts) do if st.cmd == "set" then setv[st.target] = true end end
for k in pairs(C.params) do setv[k] = true end
local unknown = {}
for _, st in ipairs(C.stmts) do
  if st.cmd == "set" then
    for _, tk in ipairs(st.toks) do
      for id in tk:gmatch("[%a_][%w_%.]*") do
        local base = id
        if not tonumber(id) and not setv[base] and not KNOWN[base] and base ~= "this" and not base:match("^[%a_]+$") == false then
          if not setv[base] and not KNOWN[base] and not C.customs[base] then unknown[base] = (unknown[base] or 0) + 1 end
        end
      end
    end
  end
end
local secs = {}
for sc in pairs(C.layouts) do secs[#secs + 1] = sc end
table.sort(secs)
local params = {}
for n, p in pairs(C.params) do params[n] = p.def end
local errs, bad, runs = {}, {}, 0
local sizes = { { 40, 10 }, { 300, 24 }, { 500, 80 }, { 1000, 300 }, { 2000, 900 } }
local tt = os.clock()
for _, sz in ipairs(sizes) do
  for _, flags in ipairs({ { recarm = 0, track_selected = 0, folderstate = 0, trans_flags = 6 }, { recarm = 1, track_selected = 1, folderstate = 1, trans_flags = 0 } }) do
    local ctx = { w = sz[1], h = sz[2], tracknch = 2, trackpanmode = 3, reaper_version = 7.2, os_type = 0, trackidx = 1, ntracks = 8, mixer_visible = 1 }
    for k, v in pairs(flags) do ctx[k] = v end
    for k, v in pairs(params) do ctx[k] = v end
    local okr, R = pcall(W.run, C, ctx, {})
    runs = runs + 1
    if not okr then errs[#errs + 1] = ("%dx%d: %s"):format(sz[1], sz[2], tostring(R)) else
      local function chk(L, nm)
        for k, v in pairs(L.vars) do
          for i = 1, 8 do local x = v[i]; if x ~= x or x == math.huge or x == -math.huge then bad[nm .. ":" .. k] = true end end
        end
      end
      chk(R.G, "G")
      for n, L in pairs(R.layouts) do chk(L, n) end
    end
  end
end
local per_run = (os.clock() - tt) / runs * 1000
local u = {}
for k, n in pairs(unknown) do u[#u + 1] = k end
table.sort(u)
local nb = 0; for _ in pairs(bad) do nb = nb + 1 end
local lay = {}
for _, sc in ipairs(secs) do lay[#lay + 1] = sc .. "=" .. #C.layouts[sc] end
print(("layouts[%s] customs=%d params=%d warn=%d errs=%d nan=%d %.0fms/run"):format(table.concat(lay, " "),
  (function() local n = 0 for _ in pairs(C.customs) do n = n + 1 end return n end)(), #C.param_order, #C.warnings, #errs, nb, per_run))
for _, e in ipairs(errs) do print("  ERR", e) end
for _, w in ipairs(C.warnings) do print("  WARN", w) end
if #u > 0 then print("  UNKNOWN ids:", table.concat(u, " "):sub(1, 600)) end
local n = 0; for k in pairs(bad) do n = n + 1; if n <= 5 then print("  NaN/inf", k) end end
