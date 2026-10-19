  --------------
  local function GetSetProjectStart(set)

      local offset=reaper.TimeMap2_beatsToTime(0,8)
      if set then
         reaper.SNM_SetDoubleConfigVar('projtimeoffs', -offset)
         reaper.UpdateTimeline()
      else
         reaper.SetEditCurPos(offset,false, false)
      end
      return offset
  end
  
  local function main()
      
      --Tempo envelope: Insert tempo marker at edit cursor, without opening tempo edit dialog
      reaper.Main_OnCommand(40256,0)
      --GetSetProjectStart(true)
  end
  
  main()
