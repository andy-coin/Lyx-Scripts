
  if not reaper.JS_Window_FindChildByID then reaper.MB("This script needs the js_ReaScriptAPI extension (install via ReaPack).","Lyx Scripts",0) return end
  local mainHWND = reaper.GetMainHwnd()
  local windowHWND = reaper.JS_Window_FindChildByID(mainHWND,1000)
  reaper.JS_Window_SetScrollPos( windowHWND, "v",0)
  
  reaper.defer(function()end)
