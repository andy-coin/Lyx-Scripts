
  r=reaper

  local function main()
  
      if reaper.CountSelectedTracks2(0,1) == 0 then return end
      
      tr=reaper.GetSelectedTrack2(0,0,1)
      
      tr_auto=reaper.GetMediaTrackInfo_Value(tr,"I_AUTOMODE")
      
        if tr_auto <= 1 then
        
           tr_all={}
           for abi=0,reaper.CountSelectedTracks2(0,1)-1 do
               tr_all[abi+1]=reaper.GetSelectedTrack2(0,abi,1)
               reaper.SetMediaTrackInfo_Value(tr_all[abi+1],"I_AUTOMODE",4)
           end
        
        elseif tr_auto >=2 then
          
           tr_all={}
           for abi=0,reaper.CountSelectedTracks2(0,1)-1 do
               tr_all[abi+1]=reaper.GetSelectedTrack2(0,abi,1)
               local n=reaper.CountSelectedMediaItems(0)
               if n==0 then
                  reaper.SetMediaTrackInfo_Value(tr_all[abi+1],"I_AUTOMODE",0)
               else
                  for abii=1,n do
                      local item=reaper.GetSelectedMediaItem(0,abii-1)
                      local take=reaper.GetActiveTake(item)
                      local env=reaper.CountTakeEnvelopes(take)
                      if env>0 then
                         reaper.SetMediaTrackInfo_Value(tr_all[abi+1],"I_AUTOMODE",1)
                         break
                      else
                         reaper.SetMediaTrackInfo_Value(tr_all[abi+1],"I_AUTOMODE",0)
                         break
                      end
                  end
               end 
           end        
        end
  
  end
  
  reaper.defer(main)
