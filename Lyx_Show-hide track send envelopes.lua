  
  r=reaper
  
  local function main()
  
      cmd=reaper.NamedCommandLookup("_BR_T_SHOW_SEND_ENV_VOL_SEL_TRACK")
      reaper.Main_OnCommand(cmd,0)
      
      for sel_tr = 1, reaper.CountSelectedTracks(0) do
        local track = reaper.GetSelectedTrack(0,sel_tr-1)
        if track then
          for i = 1,reaper.CountTrackEnvelopes( track ) do
            env = reaper.GetTrackEnvelope( track, i-1 )
            _,name=reaper.GetEnvelopeName(env)
            if name~="Send Volume" then goto NEXT end
            local br_env = reaper.BR_EnvAlloc( env, false )
            active,visible,armed,inLane,laneHeight,defaultShape,_,_,_,Type,faderScaling = reaper.BR_EnvGetProperties( br_env )
            reaper.BR_EnvSetProperties(br_env,true,visible,armed,true,150,defaultShape,faderScaling)
            reaper.BR_EnvFree( br_env, true )
            ::NEXT::
          end
        end
      end
  
  end
  
  
  reaper.defer(main)
  
