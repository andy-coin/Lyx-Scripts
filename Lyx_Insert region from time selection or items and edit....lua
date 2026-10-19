  
  r=reaper
  
  local function main()
  
      reaper.Undo_BeginBlock()
          
      Start,End=reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
      
      if Start==End then
         reaper.Main_OnCommand(41039,0)
      end
      
      reaper.Main_OnCommand(40306,0)
      
      reaper.GetSet_LoopTimeRange2(0,true,false,Start,End,false)
      
      reaper.Undo_EndBlock("Insert region from time selection or item and edit...",-1)
  
  end
  
  main()
