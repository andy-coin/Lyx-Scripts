  
  r=reaper
  if not reaper.BR_GetMouseCursorContext then reaper.MB("This script needs the SWS extension (install via ReaPack / sws-extension.org).","Lyx Scripts",0) return end
  
  local function main()
  
      env=reaper.GetSelectedEnvelope(0)
      if not env then return end
      br_env=reaper.BR_EnvAlloc(env,false)
      active,visible,armed,inLane,laneHeight,defaultShape,_,_,_,Type,faderScaling = reaper.BR_EnvGetProperties( br_env )
      if laneHeight~= 132 then
         reaper.BR_EnvSetProperties(br_env,true,true,armed,inLane,132,defaultShape,faderScaling)
      else
         reaper.BR_EnvSetProperties(br_env,true,true,armed,inLane,500,defaultShape,faderScaling)
      end
      BR=reaper.BR_EnvFree(br_env,true)
  end
  
  reaper.defer(main)
