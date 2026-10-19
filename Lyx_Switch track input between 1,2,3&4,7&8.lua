
  r=reaper
  
  local function main()
  
      if reaper.CountSelectedTracks(0)~=1 then return end
      
      tr=reaper.GetSelectedTrack(0,0)
      
      input=reaper.GetMediaTrackInfo_Value(tr,"I_RECINPUT")
      --mon=reaper.GetMediaTrackInfo_Value(tr,"I_RECMON")
      reaper.SetMediaTrackInfo_Value(tr,"I_RECMON",1)
      if input==0 then 
         reaper.SetMediaTrackInfo_Value(tr,"I_RECINPUT",1)
      elseif input==1 then
         reaper.SetMediaTrackInfo_Value(tr,"I_RECINPUT",1026)
      elseif input==1026 then 
         reaper.SetMediaTrackInfo_Value(tr,"I_RECINPUT",1030)
         reaper.SetMediaTrackInfo_Value(tr,"I_RECMON",0)
      elseif input==1030 then
         reaper.SetMediaTrackInfo_Value(tr,"I_RECINPUT",0)
      elseif input>=4096 then
         mode=reaper.GetMediaTrackInfo_Value(tr,"I_RECMODE")
         if mode==7 then
            reaper.SetMediaTrackInfo_Value(tr,"I_RECMODE",8)
         elseif mode==8 then
            reaper.SetMediaTrackInfo_Value(tr,"I_RECMODE",7)
         end
      else
         return
      end
    
  end
  
  reaper.defer(main)
