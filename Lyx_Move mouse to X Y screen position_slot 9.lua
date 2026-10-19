 
ext_name = "XR_MousePositions"

script_name = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")

slot = script_name:match("slot (%d+)")
if slot then
  slot = tonumber(slot)
  if slot then slot = math.max(math.min(32, slot), 1) else slot = 1 end
else
  slot = 1
end

function Init()
  x = reaper.GetExtState(ext_name, "x" .. slot, false)
  y = reaper.GetExtState(ext_name, "y" .. slot, false)
  aaaaaaaa = x
  if x ~= "" and y ~= "" then
    x = tonumber( x )
    y = tonumber( y )
    if x and y then
      reaper.Undo_BeginBlock()
      reaper.JS_Mouse_SetPosition( x, y )
      hwnd = reaper.JS_Window_FromPoint( x, y )
      --reaper.JS_Window_SetFocus( hwnd )--set fcous
      --reaper.JS_Window_SetForeground( hwnd )--set focus
      reaper.Undo_EndBlock("move", -1)
    end
  end
end

if not preset_file_init then
  Init()
end
