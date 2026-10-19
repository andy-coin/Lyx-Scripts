  
  r=reaper
  
  local function main()
  
      cmd=reaper.NamedCommandLookup("_BR_T_SHOW_SEND_ENV_VOL_SEL_TRACK")
      reaper.Main_OnCommand(cmd,0)
      
      for sel_tr = 1, reaper.CountSelectedTracks(0) do
        local track = reaper.GetSelectedTrack(0,sel_tr-1)
        if track then
          for i = 1,reaper.CountTrackEnvelopes( track ) do
            local env = reaper.GetTrackEnvelope( track, i-1 )
            local br_env = reaper.BR_EnvAlloc( env, false )
            active,visible,armed,inLane,laneHeight,defaultShape,_,_,_,Type,faderScaling = reaper.BR_EnvGetProperties( br_env )
            if Type==0 then
               reaper.BR_EnvSetProperties(br_env,true,true,armed,true,130,defaultShape,faderScaling)
            elseif Type~=0 and visible then
               reaper.BR_EnvSetProperties(br_env,true,true,armed,false,laneHeight,defaultShape,faderScaling)
            end         
            reaper.BR_EnvFree( br_env, true )
          end
        end
      end
  
  end
  
  
  reaper.defer(main)
