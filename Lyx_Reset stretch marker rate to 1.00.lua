  
  r=reaper
  
  local function main()
    
    reaper.BR_GetMouseCursorContext()
    take=reaper.BR_GetMouseCursorContext_Take()
    idx=reaper.BR_GetMouseCursorContext_StretchMarker()
    if not take or idx < 1 then return end
    -- source position -> item position (account for start offset and playrate)
    local offs = reaper.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS')
    local rate = reaper.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE')
    _,pos_a,a = reaper.GetTakeStretchMarker(take,idx)
    _,pos_b,b = reaper.GetTakeStretchMarker(take,idx-1)
    reaper.SetTakeStretchMarker(take,idx,(a-offs)/rate,a)
    reaper.SetTakeStretchMarker(take,idx-1,(b-offs)/rate,b)
    reaper.SetTakeStretchMarkerSlope(take,idx,0)
    reaper.SetTakeStretchMarkerSlope(take,idx-1,0)
    reaper.UpdateArrange()
    
  end
  
  if not reaper.BR_GetMouseCursorContext then reaper.MB("This script needs the SWS extension (install via ReaPack / sws-extension.org).","Lyx Scripts",0) return end
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Reset stretch marker rate to 1.00",-1)
