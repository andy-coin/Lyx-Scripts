
  local mainHWND = reaper.GetMainHwnd()
  local windowHWND = reaper.JS_Window_FindChildByID(mainHWND,1000)
  reaper.JS_Window_SetScrollPos( windowHWND, "v",0)
  
  reaper.defer(function()end)
