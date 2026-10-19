  
  r=reaper
  
  local function main()
      
      
      tr_n=reaper.CountSelectedTracks(0)
      
      if tr_n==1 then
         tr=reaper.BR_TrackAtMouseCursor() or reaper.GetSelectedTrack(0,0) -- shortcut with mouse off the tracks
         Solo=reaper.GetMediaTrackInfo_Value(tr,"B_SOLO_DEFEAT")
         reaper.SetMediaTrackInfo_Value(tr,"B_SOLO_DEFEAT",math.abs(Solo-1))
      else
         for abi=1,reaper.CountSelectedTracks(0) do
             tr=reaper.GetSelectedTrack(0,abi-1)
             Solo=reaper.GetMediaTrackInfo_Value(tr,"B_SOLO_DEFEAT")
             if Solo==0 then
                solo=1
                break
             else
                solo=0
             end
         end
         for abi=1,reaper.CountSelectedTracks(0) do
             tr=reaper.GetSelectedTrack(0,abi-1)
             reaper.SetMediaTrackInfo_Value(tr,"B_SOLO_DEFEAT",solo)
         end
      
      end
      
      reaper.Main_OnCommand(40281,0)
      reaper.Main_OnCommand(40281,0)
  end
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Toggle track solo defeat",-1)
