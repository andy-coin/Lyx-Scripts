  
  r=reaper
  
  local function main()
      
      play=reaper.GetPlayState()
      
      if play~=1 and play~=5 then
         cmd=reaper.NamedCommandLookup("_S&M_INS_MARKER_EDIT")
      else
         cmd=reaper.NamedCommandLookup("_S&M_INS_MARKER_PLAY")
      end
      
      reaper.Main_OnCommand(cmd,0)
  
  end
  
  main()
