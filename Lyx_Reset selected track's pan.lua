  
  r=reaper
  
  local function main()
  
      tr_n=reaper.CountSelectedTracks(0)
      
      if tr_n==0 then return end
      
      if tr_n==1 then
         tr=reaper.BR_TrackAtMouseCursor()
         if tr then
            reaper.SetMediaTrackInfo_Value(tr,"D_PAN",0)
            return
         end
      end
      
      for abi=1,tr_n do
          tr=reaper.GetSelectedTrack(0,abi-1)
          reaper.SetMediaTrackInfo_Value(tr,"D_PAN",0)
      end
      
  end
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Reset selected track's volume",-1)
