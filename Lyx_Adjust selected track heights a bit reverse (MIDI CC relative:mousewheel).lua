  
  function main()
    
    if not reaper.GetSelectedTrack(0,0) then return end
    
    local tr_sel = reaper.GetSelectedTrack(0,0)
      tcph = reaper.GetMediaTrackInfo_Value(tr_sel,"I_TCPH")
      tcph = math.floor(tcph)
        
    _,_,_,_,_,_,mouse_scroll  = reaper.get_action_context() 
    
    
    if mouse_scroll < 0 then
        reaper.Main_OnCommand(41327,0)
    else
        reaper.Main_OnCommand(41328,0)
    end   
    
  end
  
  reaper.defer(main)
