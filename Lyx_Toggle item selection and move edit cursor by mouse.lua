  
  r=reaper
  if not reaper.BR_GetMouseCursorContext then reaper.MB("This script needs the SWS extension (install via ReaPack / sws-extension.org).","Lyx Scripts",0) return end
  
  local function main()
      
      reaper.PreventUIRefresh(1)
      item=reaper.BR_ItemAtMouseCursor()
      sel=reaper.GetMediaItemInfo_Value(item,"B_UISEL")
      reaper.SetMediaItemSelected(item,math.abs(sel))
      reaper.UpdateArrange()
      
      track=reaper.BR_TrackAtMouseCursor()
      sel=reaper.GetMediaTrackInfo_Value(track,"I_SELECTED")
      if sel==1 then
         reaper.SetTrackSelected(track,false)
      end
      reaper.PreventUIRefresh(-1)
      reaper.Main_OnCommand(40514,0)
  end
  
  main()
