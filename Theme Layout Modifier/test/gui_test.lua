-- Offline GUI check (fake ImGui in mock/). Run from the project folder with a standalone Lua 5.4:
--   lua test/gui_test.lua test
-- Needs the JRENG!_Metric theme in "/Applications/REAPER/ColorThemes 2".
local SP = arg[1]
package.path = SP .. "/mock/?.lua;" .. package.path
local ext = { Lyx_ThemeLayoutModifier = { dir = "/Applications/REAPER/ColorThemes 2", sec = "mcp" } }
local deferred
reaper = setmetatable({
  ImGui_GetBuiltinPath = function() return SP .. "/mock" end,
  GetExtState = function(s, k) return (ext[s] or {})[k] or "" end,
  SetExtState = function(s, k, v) ext[s] = ext[s] or {}; ext[s][k] = v end,
  GetResourcePath = function() return "/Applications/REAPER" end,
  -- raw ReaImGui calls made by _Lyx_GUI's G.pin / G.pin_flag
  ImGui_GetFrameHeight = function() return 20 end, ImGui_GetItemRectMin = function() return 0, 0 end,
  ImGui_WindowFlags_TopMost = function() return 1 << 30 end,
  GetAppVersion = function() return "7.20/macOS-arm64" end,
  GetLastColorThemeFile = function() return "/Applications/REAPER/ColorThemes 2/JRENG!_Metric.ReaperTheme" end,
  defer = function(f) deferred = f end, time_precise = os.clock,
  new_array = function(n) local t = {}; for i = 1, n do t[i] = 0 end; return t end,
  EnumerateFiles = function(dir, i)
    local p = io.popen('ls -1 "' .. dir .. '"'); local n = 0
    for l in p:lines() do if l:match("%.ReaperTheme") or l:match("%.ReaperThemeZip") then if n == i then p:close() return l end n = n + 1 end end
    p:close()
  end,
}, { __index = function(_, k) return function() end end })
dofile("/Applications/REAPER/Scripts/Lyx Scripts/Theme Layout Modifier/Lyx_Theme Layout Modifier.lua")
local function up(f, name, seen)
  seen = seen or {}
  if seen[f] then return end
  seen[f] = true
  for i = 1, 300 do
    local n, v = debug.getupvalue(f, i); if not n then break end
    if n == name then return v end
  end
  for i = 1, 300 do
    local n, v = debug.getupvalue(f, i); if not n then break end
    if type(v) == "function" then local r = up(v, name, seen); if r ~= nil then return r end end
  end
end
local function frame(n) for _ = 1, n or 1 do local f = deferred; deferred = nil; f() end end
frame(2)
local S, P = up(deferred, "S"), up(deferred, "P")
local draw_edit = up(deferred, "draw_edit")
local draw_canvas = up(draw_edit, "draw_canvas")
local Tget = function() return up(deferred, "T") end
-- load JRENG if not loaded
local T = Tget()
if not T then
  local try = up(up(deferred, "draw_header") or deferred, "try_select_theme")
  for i, t in ipairs(S.themes) do if t.name:find("JRENG!_Metric$") then try(i) end end
  T = Tget()
end
assert(T, "theme not loaded")
S.page, S.sel_layout = "edit", "A - Analog"
frame(3)
print("MCP size", P.W, P.H)
for k, v in pairs(SIM.bal) do assert(v == 0, "unbalanced " .. k .. " " .. v) end
-- select label, check anchor enabled (BeginDisabled for anchor must be false, not nil)
S.sel_elem = "mcp.label"; SIM.calls.disabled = {}
frame(1)
for _, d in ipairs(SIM.calls.disabled) do assert(d ~= nil, "BeginDisabled got nil") end
-- frame drag on MCP: grab bottom edge, pull down 300 screen px
local z = P.zoom
local px, py = P.org_x, P.org_y
local bottom = py + P.H * z
SIM.hover = true; SIM.mouse = { px + P.W * z / 2, bottom }; SIM.clicked[0] = true; SIM.down[0] = true
frame(1); SIM.clicked[0] = false
SIM.mouse = { px + P.W * z / 2, bottom + 300 * z }; frame(1)
SIM.down[0] = false; frame(1)
print("after bottom drag", P.W, P.H)
assert(P.H > 600, "height still capped")
-- right edge must not resize on MCP
local W0 = P.W
SIM.mouse = { px + P.W * z, py + 50 }; SIM.clicked[0] = true; SIM.down[0] = true; frame(1); SIM.clicked[0] = false
SIM.mouse = { px + P.W * z + 100, py + 50 }; frame(1); SIM.down[0] = false; frame(1)
assert(P.W == W0, "MCP width changed")
-- shift + corner drag on the mute button keeps ratio
local drag_element = up(draw_canvas, "drag_element")
local erect, LS = up(draw_canvas, "erect"), up(draw_canvas, "LS")
local evaluate = up(deferred, "evaluate")
local l, t, r, b = erect(LS("A - Analog"), "mcp.mute")
local d = { kind = "elem", e = "mcp.mute", mode = "rb", sx = 0, sy = 0, done = { 0, 0, 0, 0 }, w0 = r - l, h0 = b - t }
for step = 1, 4 do drag_element("A - Analog", d, step * 10 * z, 2 * z, z, true); evaluate() end
local l2, t2, r2, b2 = erect(LS("A - Analog"), "mcp.mute")
print(("mute %dx%d -> %dx%d"):format(r - l, b - t, r2 - l2, b2 - t2))
assert(math.abs((r2 - l2) / (b2 - t2) - (r - l) / (b - t)) < 0.05, "ratio not kept")
assert(l2 == l and t2 == t, "rb drag moved the origin")
-- right-drag pan moves the panel
local ox0 = P.org_x
SIM.mouse = { 500, 500 }; SIM.clicked[1] = true; SIM.down[1] = true; SIM.delta = { 40, 0 }; frame(1); SIM.clicked[1] = false; frame(1)
SIM.down[1] = false; SIM.delta = { 0, 0 }; frame(1)
print("pan org_x", ox0, "->", P.org_x)
assert(P.org_x > ox0, "pan did nothing")
for k, v in pairs(SIM.bal) do assert(v == 0, "unbalanced " .. k .. " " .. v) end
print("ALL OK")
local render_panel = up(draw_canvas, "render_panel")
P.H = 874; T.dirty_eval = true; evaluate()
local out = render_panel({}, "A - Analog", 0, 0, 1, { 0, 0, 2000, 2000 })
for _, o in ipairs(out) do
  if o.e == "mcp.label" or o.e == "mcp.volume" then
    print(o.e, "hit rect", o.l, o.r)
    assert(o.l >= 0 and o.r <= P.W, o.e .. " not clipped to panel")
  end
end
for k, v in pairs(SIM.bal) do assert(v == 0, "unbalanced " .. k .. " " .. v) end
print("CLIP OK")
-- snapping: drag mute so its left edge lands 1 px right of the panel's left edge -> snaps to 0
S.snap = true
local snap_targets = up(draw_canvas, "snap_targets")
local L = LS("A - Analog")
local l, t, r, b = erect(L, "mcp.mute")
local xs, ys = snap_targets(L, "mcp.mute")
local d = { kind = "elem", e = "mcp.mute", mode = "move", sx = 0, sy = 0, done = { 0, 0, 0, 0 },
  l0 = l, t0 = t, w0 = r - l, h0 = b - t, xs = xs, ys = ys }
drag_element("A - Analog", d, (1 - l) * z, 0, z, false); evaluate()
local l2, _, r2 = erect(LS("A - Analog"), "mcp.mute")
print("snap: left edge", l, "->", l2, "snap_x", d.snap_x)
assert(d.snap_x and (l2 == d.snap_x or r2 == d.snap_x), "did not snap") -- closest edge wins (left or right)
S.snap = false
d = { kind = "elem", e = "mcp.mute", mode = "move", sx = 0, sy = 0, done = { 0, 0, 0, 0 },
  l0 = l2, t0 = t, w0 = r - l, h0 = b - t, xs = xs, ys = ys }
drag_element("A - Analog", d, 1 * z, 0, z, false); evaluate()
assert(erect(LS("A - Analog"), "mcp.mute") == l2 + 1 and not d.snap_x, "free mode still snapped")
-- inspector with nothing selected must not leave a dangling SameLine (rows overlapped)
S.sel_elem = nil; frame(2)
for k, v in pairs(SIM.bal) do assert(v == 0, "unbalanced " .. k .. " " .. v) end
print("SNAP OK")
-- pinned window: TopMost flag path runs without errors
ext.Lyx_GUI = { ["pin:ThemeLayoutModifier"] = "1" }; frame(2)
for k, v in pairs(SIM.bal) do assert(v == 0, "unbalanced " .. k .. " " .. v) end
print("PIN OK")
-- transport: tab, main page, edit page, element list, width presets, state rules row gone
local switch_section = up(deferred, "switch_section") or up(up(deferred, "draw_main"), "switch_section")
S.page = "main"; switch_section("trans"); frame(2)
print("trans size", P.W, P.H, "layouts", #(T.C.layouts.trans or {}))
assert(P.W >= 1000 and P.H > 0, "transport size not read")
S.page, S.sel_layout = "edit", T.C.layouts.trans[1]; frame(2)
local out = render_panel({}, S.sel_layout, 0, 0, 1, { 0, 0, 3000, 3000 })
local got = {}
for _, o in ipairs(out) do got[o.e] = true end
for _, e in ipairs({ "trans.play", "trans.stop", "trans.rec", "trans.status", "trans.bpm.edit" }) do assert(got[e], e .. " not drawn") end
S.sel_elem = "trans.play"; frame(2)
P.tflags = 0; T.dirty_eval = true; frame(1); P.tflags = 6; T.dirty_eval = true; frame(1)
for k, v in pairs(SIM.bal) do assert(v == 0, "unbalanced " .. k .. " " .. v) end
print("TRANS OK")
