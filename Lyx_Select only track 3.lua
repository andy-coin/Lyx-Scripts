  
  function main()
    
    cmd=reaper.NamedCommandLookup("_SWS_SEL3")
    reaper.Main_OnCommand(cmd,0)
    
    tr=reaper.GetSelectedTrack(0,0)
    
    reaper.SetMixerScroll(tr)
    
  end
  
  reaper.defer(main)
