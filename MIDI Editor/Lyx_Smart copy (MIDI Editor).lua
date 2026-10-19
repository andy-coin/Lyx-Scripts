
  r=reaper
  
  local function main()
      
      E=reaper.MIDIEditor_GetActive()
      if not E then return end
      win,seg,detail=reaper.BR_GetMouseCursorContext()
      if win~="midi_editor" then return end
      
      if seg~="cc_lane" then
         reaper.MIDIEditor_OnCommand(E,40010)
      else
         cmd=reaper.NamedCommandLookup("_RS7d3c_1d318cf39d0ffba5edc67e6be0dd4510cea865dc")
         reaper.MIDIEditor_OnCommand(E,cmd)
      end
  end
  
  main()
