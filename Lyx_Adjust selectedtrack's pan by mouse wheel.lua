  r=reaper
  
  -------------------------------------------------------------------- 
  local function main()
    
    tr_n=reaper.CountSelectedTracks(0)
    
    if tr_n==0 then return end
    
    if tr_n==1 then
       cur_tr=reaper.GetSelectedTrack(0,0)
       tr=reaper.BR_TrackAtMouseCursor()
       if tr then
          reaper.SetOnlyTrackSelected(tr)
       end
    end
    _,_,_,_,_,_,mouse_scroll  = reaper.get_action_context() 
    
    times=reaper.GetExtState("Abi","Abi",false) 
    times=tonumber(times)
    
    if type(times)~="number" then
       times = 0
    end
    
    if times%3==0 then
       if mouse_scroll < 0 then
          reaper.Main_OnCommand(40283,0)
          reaper.Main_OnCommand(40283,0)
       else
          reaper.Main_OnCommand(40284,0)
          reaper.Main_OnCommand(40284,0)
       end
    end 
    
    if cur_tr then
       reaper.SetOnlyTrackSelected(cur_tr)
    end
    
    times=times+1
    reaper.SetExtState("Abi","Abi",times,false) 
    
  end
  
  reaper.defer(main)
