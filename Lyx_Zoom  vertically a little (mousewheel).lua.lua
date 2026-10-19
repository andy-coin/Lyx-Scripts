
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  ---CUSTOM---
      zoom_adjust = 7 --integer and > 1
      zoom_adjust = (zoom_adjust>0 and math.floor(zoom_adjust)) or 3
      
      reverse = false
      
      reverse = (reverse and -1) or 1
      
  
  -------------------------------------------------------------------- 
  local function main()
      
      r.SaveTracks(true)

      local tr = reaper.BR_GetMouseCursorContext_Track() or api.gst(0,0) or api.gt(0,0)
      if not tr then return end
      
      tcph = api.gtv(tr,"I_TCPH")
      tcpy_1 = api.gtv(tr,"I_TCPY")
      _,ori_position = reaper.JS_Window_GetScrollInfo( windowHWND, "v" )
      
      _,_,_,_,_,_,wheel  = reaper.get_action_context() 
      
      wheel = wheel * reverse
      
      zoom = ( wheel < 0 and 41327) or 41328
      --api.cmd(40296,0)
      api.cmd(api.name('_SWS_SELCHILDREN2'),0)--select children
      for abii=1,zoom_adjust do
          api.cmd(zoom,0)
      end
      
      reaper.JS_Window_SetScrollPos( windowHWND, "v", ori_position )
      tcpy_2 = api.gtv(tr,"I_TCPY")
      scroll=tcpy_2-tcpy_1
      reaper.JS_Window_SetScrollPos( windowHWND, "v", ori_position+scroll )
      
      r.RestoreTracks(true)

      api.ua()
    
  end
  
  window     = reaper.BR_GetMouseCursorContext()
  mainHWND   = reaper.GetMainHwnd()
  windowHWND = reaper.JS_Window_FindChildByID(mainHWND,1000)
  
  if  window ~= "midi_editor" then
      main()
  end
  
  reaper.defer(function()end)
