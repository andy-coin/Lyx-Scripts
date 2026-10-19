  
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path .. ";" .. script_path .. "?.lua"
  local r=require("_Lyx_HOME")
  
  speed_control = 4
  local function main()
  
      _,_,_,_,_,_,mouse_wheel  = reaper.get_action_context() 
      
      editor=reaper.GetExtState("editor_toggle",pro_name,false)
      
      --if not reaper.MIDIEditor_GetActive() and editor=="1" then return end
      
      times=math.floor(mouse_wheel/speed_control)
      reaper.CSurf_OnScroll(0,-times)

  end
  
  reaper.defer(main)
