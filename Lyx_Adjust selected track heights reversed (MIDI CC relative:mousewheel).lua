  r=reaper
  
  -------------------------------------------------------------------- 
  local function main()
    
    tr_n=reaper.CountSelectedTracks(0)
    
    if tr_n==0 then return end
    
    _,_,_,_,_,_,mouse_scroll  = reaper.get_action_context() 
    
    times=reaper.GetExtState("Abi","Abi",false) 
    times=tonumber(times)
    
    if type(times)~="number" then
       times = 0
    end
    
    if times%3==0 then
       if mouse_scroll > 0 then
          cmd=reaper.NamedCommandLookup("_XENAKIOS_NUDGSELTKVOLUP")
          reaper.Main_OnCommand(cmd,0)
       else
         cmd=reaper.NamedCommandLookup("_XENAKIOS_NUDGSELTKVOLDOWN")
         reaper.Main_OnCommand(cmd,0)
       end
    end 
    
    for abi=1,tr_n do
        tr=reaper.GetSelectedTrack(0,abi-1)
        VOL=reaper.GetMediaTrackInfo_Value(tr,"D_VOL")
        if VOL>3.981071705535 then
           reaper.SetMediaTrackInfo_Value(tr,"D_VOL",3.981071705535)
        end
    end
    
    times=times+1
    reaper.SetExtState("Abi","Abi",times,false) 
    
  end
  
  reaper.defer(main)
  --tr=reaper.GetSelectedTrack(0,0)
  --reaper.ShowConsoleMsg(reaper.GetMediaTrackInfo_Value(tr,"D_VOL"))
  

  
  
  
  
