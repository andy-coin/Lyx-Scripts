
  r=reaper
  
  local function main()
      
      if reaper.CountSelectedTracks(0)==0 then return end
      
      TWIN={}
      
      for abi=1,reaper.CountSelectedTracks(0) do
          
          tr=reaper.GetSelectedTrack(0,abi-1)
          
          if reaper.GetMediaTrackInfo_Value(tr,"I_FOLDERDEPTH")~=1 then goto NEXT end
          
          idx=reaper.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER")
          color=reaper.GetTrackColor(tr)
          _,name=reaper.GetSetMediaTrackInfo_String(tr,"P_NAME","",false)
          
          reaper.InsertTrackAtIndex(idx-1,true)
          
          twin=reaper.GetTrack(0,idx-1)
          reaper.SetTrackColor(twin,color)
          reaper.GetSetMediaTrackInfo_String(twin,"P_NAME",name,true)
          
          reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", 0)
          send = reaper.CreateTrackSend(tr, twin)
          reaper.SetTrackSendInfo_Value(tr, 0, send, "D_VOL", 1)
          reaper.SetTrackSendInfo_Value(tr, 0, send, "I_SENDMODE", 0)
          TWIN[#TWIN+1]=twin
          
          ::NEXT::
      end
      
      reaper.Main_OnCommand(40297,0)
      
      for abi=1,#TWIN do
          reaper.SetTrackSelected(TWIN[abi],true)
      end    
      
      reaper.ReorderSelectedTracks(0,0)
      
  end
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Create a twin brother for selected parent tracks",-1)
