  
  r=reaper
  
  local function main()
    
    reaper.BR_GetMouseCursorContext()
    take=reaper.BR_GetMouseCursorContext_Take()
    idx=reaper.BR_GetMouseCursorContext_StretchMarker()
    _,pos_a,a = reaper.GetTakeStretchMarker(take,idx)
    _,pos_b,b = reaper.GetTakeStretchMarker(take,idx-1)
    reaper.SetTakeStretchMarker(take,idx,a)
    reaper.SetTakeStretchMarker(take,idx-1,b)
    reaper.SetTakeStretchMarkerSlope(take,idx,0)
    reaper.SetTakeStretchMarkerSlope(take,idx-1,0)
    reaper.UpdateArrange()
    
  end
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Reset stretch marker rate to 1.00",-1)
