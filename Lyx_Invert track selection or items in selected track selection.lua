
  r=reaper
  
  local function main()
  
  
      area=reaper.BR_GetMouseCursorContext()
      it_n=reaper.CountSelectedMediaItems(0)
      
      if reaper.CountSelectedMediaItems(0)==0 or area=="tcp" or area=="mcp" then
         Obj="track"
         cmd=reaper.NamedCommandLookup("_SWS_TOGTRACKSEL")
         --reaper.Main_OnCommand(cmd,0)
         for abi=1,reaper.CountTracks(0) do
             tr=reaper.GetTrack(0,abi-1)
             selected=reaper.GetMediaTrackInfo_Value(tr,"I_SELECTED")
             reaper.SetMediaTrackInfo_Value(tr,"I_SELECTED",math.abs(selected-1))
             parent=reaper.GetParentTrack(tr)
             if parent then
                if reaper.GetMediaTrackInfo_Value(tr,"B_SHOWINTCP")==0.0 then 
                   reaper.SetMediaTrackInfo_Value(tr,"I_SELECTED",0)
                elseif reaper.GetMediaTrackInfo_Value(parent,"I_FOLDERCOMPACT")~=0 then
                   selected=reaper.GetMediaTrackInfo_Value(parent,"I_SELECTED")
                   reaper.SetMediaTrackInfo_Value(tr,"I_SELECTED",math.abs(selected))
                end
             end
         end
      else
         Obj="item"
         itemz={}
         for abi = 1,it_n do
             itemz[abi] = reaper.GetSelectedMediaItem(0,abi-1)
         end
         for abi=1,#itemz do
             item_track = reaper.GetMediaItem_Track(itemz[abi])
             if last_tr and last_tr==item_track then
                goto NEXT
             end
             for abigel=1,reaper.CountTrackMediaItems(item_track) do
                 tmp=reaper.GetTrackMediaItem(item_track,abigel-1)
                 selected= reaper.GetMediaItemInfo_Value(tmp,"B_UISEL")
                 reaper.SetMediaItemInfo_Value(tmp,"B_UISEL",math.abs(selected-1))
             end
             reaper.UpdateArrange()
             ::NEXT::
             last_tr=item_track
         end
        
      end
  
  end
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Invert "..Obj.." Selection",-1)
