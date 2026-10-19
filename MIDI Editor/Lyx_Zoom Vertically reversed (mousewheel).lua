  
  r=reaper
   
   reverse = false
   
   reverse = (reverse and -1) or 1
   
  local function midi()
  
    _,_,_,_,_,_,mouse_scroll  = reaper.get_action_context()
    
    mouse_scroll = mouse_scroll * reverse
    
    extname="abi"
    abi=reaper.GetExtState(extname,"abi",false) 
    abi=tonumber(abi)
    
    if type(abi)~="number" then
      abi = 0
    end
    
    E=reaper.MIDIEditor_GetActive()
    --if abi%2==0 then
      
      if mouse_scroll < 0 then
        reaper.MIDIEditor_OnCommand(E,40111)--increase
        reaper.MIDIEditor_OnCommand(E,40111)--increase
      else -- mouse_scroll > 0 
        reaper.MIDIEditor_OnCommand(E,40112)--decrease
        reaper.MIDIEditor_OnCommand(E,40112)--decrease
      end
    
    --end
    --abi=abi%2+1
    --reaper.SetExtState(extname,"abi",abi,false)
    
  end
  
  window,_,_=reaper.BR_GetMouseCursorContext()
  
  if  window == "midi_editor" then
      reaper.defer(midi)
  end
