
  local function main()
  
      local ME = reaper.MIDIEditor_GetActive()
      if not ME then return end
      local take =  reaper.MIDIEditor_GetTake( ME )
      
      local grid, swing, noteLen = reaper.MIDI_GetGrid ( take )
      
      local triplet = ((1/grid)/3)%1==0
      
      if grid<=8 and grid>0.03125 then
         reaper.SetMIDIEditorGrid( 0,grid/8)
      else
         return 
      end
      
      if triplet then reaper.MIDIEditor_OnCommand(ME,41004) end
      if swing ~= 0 then reaper.MIDIEditor_OnCommand(ME,41006) end

  end
  
  reaper.defer(main)
