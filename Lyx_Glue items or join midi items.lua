
  r=reaper
  
  local function JoinItems(haed)
      
      tmp_n=reaper.CountSelectedMediaItems(0)
      if tmp_it_n<=1 then return end 
      if not head then
         reaper.Main_OnCommand(40362,0)--Glue items
      else
         for abiiii=1,tmp_n-1 do
             tmp=reaper.GetSelectedMediaItem(0,abiiii-1)
             tmptake=reaper.GetActiveTake(tmp)
             _,ALL,_,_ = reaper.MIDI_CountEvts(t)
             for abii =1,ALL do 
               local _,selected,_,_,_,_,pitch,_ = reaper.MIDI_GetNote(t,abii-1)
               if high<pitch then high=pitch end
               if low>pitch then low=pitch end
               if selected then 
                 n[#n+1] = pitch 
               end
             end
             for abi=1,In do
               t = reaper.GetActiveTake(midi_item[abi])
               _,ALL,_,_ = reaper.MIDI_CountEvts(t)
               
               for abii =1,ALL do 
                 local _,selected,_,_,_,_,pitch,_ = reaper.MIDI_GetNote(t,abii-1)
                 if high<pitch then high=pitch end
                 if low>pitch then low=pitch end
                 if selected then 
                   n[#n+1] = pitch 
                 end
               end
             end
         end
      end
      
  end
  
  
  local function main()
      
      it_n=reaper.CountSelectedMediaItems(0)
      if it_n>1 then
         trz={}
         for abi=1,reaper.CountSelectedTracks(0) do
             trz[abi]=reaper.GetSelectedTrack(0,abi-1)
         end
         itz={}
         for abi=1,reaper.CountSelectedMediaItems(0) do
             itz[abi]=reaper.GetSelectedMediaItem(0,abi-1)
         end
         cmd = reaper.NamedCommandLookup("_SWS_SELTRKWITEM")
         reaper.Main_OnCommand(cmd,0)--Select only track(s) with selected item(s)
         trackz={}
         for abi=1,reaper.CountSelectedTracks(0) do
             trackz[abi]=reaper.GetSelectedTrack(0,abi-1)
         end
         if #trackz==#itz then return end
         abii=1
         for abi=1,tr_n do
             reaper.Main_OnCommand(40289,0)--unselect all items
             reaper.SetOnlyTrackSelected(trackz[abi])
             reaper.SetMediaItemSelected(itz[abii],true)
             Take=reaper.GetActiveTake(itz[abii])
             Source=reaper.GetMediaItemTake_Source(Take)
             TYPE=reaper.GetMediaSourceType(Source)
             abiii=1
             repeat
                 next_tr=reaper.GetMediaItemTrack(itz[abii+abiii])
                 take=reaper.GetActiveTake(itz[abii+abiii])
                 source=reaper.GetMediaItemTake_Source(take)
                 Type=reaper.GetMediaSourceType(source)
                 if trackz[abi]==next_tr and TYPE==Type then
                    reaper.SetMediaItemSelected(itz[abii+abiii],true)
                 else
                    abii=abii+abiii
                    break
                 end
                 abiii=abiii+1
             until abii+abiii>#itz
             if TYPE~="MIDI" and TYPE~="VEDIO" then
                --JoinItems()
             elseif TYPE=="MIDI" then
                --JoinItems(itz[abii],itz[abii+abiii])
             end
         end
         reaper.Main_OnCommand(40289,0)--unselect all items
         for abi=1,#itemz do
             reaper.SetMediaItemSelected(itemz[abi],true)
         end
      end
  end
