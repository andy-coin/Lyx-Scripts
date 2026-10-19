  
  r=reaper
  if not reaper.BR_GetMouseCursorContext then reaper.MB("This script needs the SWS extension (install via ReaPack / sws-extension.org).","Lyx Scripts",0) return end
  
  local function main()
      
      IN=reaper.CountSelectedMediaItems(0)
      local sel,need={},{}
      
      for abi=1,IN do
      
          local it=reaper.GetSelectedMediaItem(0,abi-1)
          local tk=reaper.GetActiveTake(it)
          local EN=(tk and reaper.CountTakeEnvelopes(tk)) or 0
          
          sel[#sel+1]=it
          clean=tk~=nil
          
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
          
          if clean then need[#need+1]=it end
      end
      
      -- items without the envelope: run the S&M show command once, on those items only
      if #need>0 then
         reaper.SelectAllMediaItems(0,false)
         for i=1,#need do reaper.SetMediaItemSelected(need[i],true) end
         reaper.Main_OnCommand(reaper.NamedCommandLookup("_S&M_TAKEENVSHOW1"),0)
         for i=1,#sel do reaper.SetMediaItemSelected(sel[i],true) end
         reaper.UpdateArrange()
      end
  
  end
  
  main()
  
  reaper.defer(function()end)
  
