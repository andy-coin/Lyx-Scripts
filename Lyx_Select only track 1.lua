  
  function main()
    
    cmd=reaper.NamedCommandLookup("_SWS_SEL1")
    reaper.Main_OnCommand(cmd,0)
    
    tr=reaper.GetSelectedTrack(0,0)

    if tr then reaper.SetMixerScroll(tr) end
    
    reaper.Main_OnCommand(40913,0)
    
  end
  
  reaper.defer(main)
