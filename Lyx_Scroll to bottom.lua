
  local mainHWND = reaper.GetMainHwnd()
  local windowHWND = reaper.JS_Window_FindChildByID(mainHWND,1000)
  local _,_,_,_,max = reaper.JS_Window_GetScrollInfo( windowHWND, "v" )
  reaper.JS_Window_SetScrollPos( windowHWND, "v",max)
  
  reaper.defer(function()end)
