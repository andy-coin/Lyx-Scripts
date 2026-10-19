  
  r=reaper
  
  --------------
  local function Jump(P)
  
      play=reaper.GetPlayState()
      local Start,End=reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
      if P>Start then return end
      if play~=1 then 
         return 
      else
         local purple=16449756
         local ts=reaper.GetThemeColor("col_tl_bgsel2")
         local p=reaper.GetPlayPosition()
         if ts==purple then 
            if p<Start and Start~=End then
               reaper.defer(function() Jump(P) end)
            else
               reaper.SetEditCurPos(End,false,true)
               reaper.SetEditCurPos(P,false,false)
            end
         else
            reaper.defer(function() Jump(P) end)
         end
      end
      
  end
  
  --------------
  local function main()
    
    local P = reaper.GetCursorPosition()
        
    if 5 == Play then
       
       return 
       
    elseif Play == 1 then
       reaper.Main_OnCommand(1016,0)
       reaper.Main_OnCommand(1007,0)
       Jump(P)
       
    else
       reaper.Main_OnCommand(1007,0)
       Jump(P)
       
    end
    
    reaper.Main_OnCommand(41330,0)--New recording splits existing items and creates new takes (default)
    --reaper.Undo_EndBlock("Play/Stop",-1)
  end
  
  
  reaper.defer(main)


