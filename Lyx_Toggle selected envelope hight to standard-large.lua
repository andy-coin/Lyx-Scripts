  
  r=reaper
  
  local function main()
  
      env=reaper.GetSelectedEnvelope(0,0)
      br_env=reaper.BR_EnvAlloc(env,false)
      active,visible,armed,inLane,laneHeight,defaultShape,_,_,_,Type,faderScaling = reaper.BR_EnvGetProperties( br_env )
      if laneHeight~= 130 then
         reaper.BR_EnvSetProperties(br_env,true,true,armed,inLane,132,defaultShape,faderScaling)
      else
         reaper.BR_EnvSetProperties(br_env,true,true,armed,inLane,500,defaultShape,faderScaling)
      end
      BR=reaper.BR_EnvFree(br_env,true)
  end
  
  reaper.defer(main)
