
  if not reaper.JS_Window_FindChildByID then reaper.MB("This script needs the js_ReaScriptAPI extension (install via ReaPack).","Lyx Scripts",0) return end
  local mainHWND = reaper.GetMainHwnd()
  local windowHWND = reaper.JS_Window_FindChildByID(mainHWND,1000)
  local _,_,_,_,max = reaper.JS_Window_GetScrollInfo( windowHWND, "v" )
  reaper.JS_Window_SetScrollPos( windowHWND, "v",max)
  
  reaper.defer(function()end)
