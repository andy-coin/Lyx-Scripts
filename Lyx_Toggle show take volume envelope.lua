  
  r=reaper
  
  local function main()
      
      IN=reaper.CountSelectedMediaItems(0)
      
      for abi=1,IN do
      
          local it=reaper.GetSelectedMediaItem(0,abi-1)
          local tk=reaper.GetActiveTake(it)
          local EN=reaper.CountTakeEnvelopes(tk)
          
          clean=true
          
          for abigel=1,EN do
              tmpenv=reaper.GetTakeEnvelope(tk,abigel-1)
              _,name=reaper.GetEnvelopeName(tmpenv)
              local br_tmpenv = reaper.BR_EnvAlloc(tmpenv, false)
              local active, visible, armed, inLane, laneHeight, defaultShape, _, _, _, _, faderScaling = reaper.BR_EnvGetProperties(br_tmpenv)
              if name=="Volume" then 
                 clean=false
                 reaper.BR_EnvSetProperties(br_tmpenv, active, not visible, armed, inLane, laneHeight, defaultShape, faderScaling)
              else
                 reaper.BR_EnvSetProperties(br_tmpenv, active, false, armed, inLane, laneHeight, defaultShape, faderScaling)
              end
              reaper.BR_EnvFree(br_tmpenv, true)
          end
          
          if clean then
             cmd=reaper.NamedCommandLookup("_S&M_TAKEENVSHOW1")
             reaper.Main_OnCommand(cmd,0)
          end
      end
  
  end
  
  main()
  
  reaper.defer(function()end)
  
