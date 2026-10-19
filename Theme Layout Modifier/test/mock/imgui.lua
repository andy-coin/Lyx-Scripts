-- minimal ReaImGui stand-in for offline runs: records push/pop balance, mouse state is scriptable
local M = {}
SIM = SIM or { mouse = { 0, 0 }, mods = 0, down = {}, clicked = {}, delta = { 0, 0 }, bal = {}, calls = {} }
local function bal(k, n) SIM.bal[k] = (SIM.bal[k] or 0) + n end
local const_id = 0
local F = {
  CreateContext = function() return {} end, CreateFont = function() return {} end, CreateImage = function() return {} end,
  Image_GetSize = function() return 30, 30 end,
  Begin = function() return true, true end,
  BeginChild = function() bal("child", 1); return true end, EndChild = function() bal("child", -1) end,
  BeginDisabled = function(_, d) SIM.calls.disabled = SIM.calls.disabled or {}; table.insert(SIM.calls.disabled, d); bal("dis", 1) end,
  EndDisabled = function() bal("dis", -1) end,
  PushStyleColor = function() bal("col", 1) end, PopStyleColor = function(_, n) bal("col", -(n or 1)) end,
  PushStyleVar = function() bal("var", 1) end, PopStyleVar = function(_, n) bal("var", -(n or 1)) end,
  PushID = function() bal("id", 1) end, PopID = function() bal("id", -1) end,
  PushFont = function() bal("font", 1) end, PopFont = function() bal("font", -1) end,
  DrawList_PushClipRect = function() bal("clip", 1) end, DrawList_PopClipRect = function() bal("clip", -1) end,
  GetContentRegionAvail = function() return 800, 600 end, GetWindowPos = function() return 0, 0 end,
  GetWindowSize = function() return 1000, 800 end, GetCursorScreenPos = function() return 0, 0 end,
  GetMousePos = function() return SIM.mouse[1], SIM.mouse[2] end, GetFrameHeight = function() return 20 end,
  GetFontSize = function() return 13 end, GetKeyMods = function() return SIM.mods end, GetMouseWheel = function() return 0 end,
  GetMouseDelta = function() return SIM.delta[1], SIM.delta[2] end, GetConfigVar = function() return 7.0 end,
  GetScrollX = function() return 0 end, GetScrollY = function() return 0 end,
  GetScrollMaxX = function() return 0 end, GetScrollMaxY = function() return 0 end,
  CalcTextSize = function(_, s) return 7 * #tostring(s), 13 end,
  IsMouseDown = function(_, b) return SIM.down[b] or false end, IsMouseClicked = function(_, b) return SIM.clicked[b] or false end,
  IsItemHovered = function() return SIM.hover or false end,
  Checkbox = function(_, _, v) return false, v end, DragInt = function(_, _, v) return false, v end,
  SliderInt = function(_, _, v) return false, v end,
  SetMouseCursor = function(_, c) SIM.cursor = c end,
  SetScrollX = function(_, v) SIM.scrollx = v end, SetScrollY = function(_, v) SIM.scrolly = v end,
}
setmetatable(M, { __index = function(_, k)
  if F[k] then return F[k] end
  if k:match("^%u%w*_%w") and not k:match("^DrawList_") and not k:match("^Image_") then
    const_id = const_id + 1; local v = 1 << (const_id % 30); rawset(M, k, v); return v
  end
  if k:match("^Begin") then return function() return false end end
  if k:match("^Is") or k:match("Button$") or k == "Selectable" or k == "CollapsingHeader" or k == "TreeNode" then
    return function() return false end end
  if k:match("^Get") then return function() return 0, 0 end end
  return function() end
end })
return function() return M end
