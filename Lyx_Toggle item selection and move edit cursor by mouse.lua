  
  r=reaper
  
  local function main()
      
      reaper.PreventUIRefresh(1)
      local mx,my=reaper.GetMousePosition()
      item=reaper.GetItemFromPoint(mx,my,true)
      sel=reaper.GetMediaItemInfo_Value(item,"B_UISEL")
      reaper.SetMediaItemSelected(item,math.abs(sel))
      reaper.UpdateArrange()
      
      track=reaper.GetTrackFromPoint(mx,my)
      sel=reaper.GetMediaTrackInfo_Value(track,"I_SELECTED")
      if sel==1 then
         reaper.SetTrackSelected(track,false)
      end
      reaper.PreventUIRefresh(-1)
      reaper.Main_OnCommand(40514,0)
  end
  
  main()
