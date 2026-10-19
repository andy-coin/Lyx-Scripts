if reaper.GetSelectedMediaItem(0,0) then
     commandID = reaper.NamedCommandLookup("_SWS_TRIPLESPLIT")
     reaper.Main_OnCommand(0, 0) 
     name = reaper.ReverseNamedCommandLookup(commandID)
     
     reaper.UpdateTimeline()
     
    -- reaper.Main_OnCommand(40196, 0)
else
   
end
