  
  r=reaper
  
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

  --------------
  local function RenewCueState()
  
      reaper.Main_OnCommand(40339,0)--unmute all tracks
      reaper.Main_OnCommand(40340,0)--unsolo all tracks
      reaper.Main_OnCommand(40182,0)--select all items
      reaper.Main_OnCommand(40689,0)--unlock items
      reaper.Main_OnCommand(40289,0)--unselect all items
      
      local max=3600*12
      first_measure=GetSetProjectStart()

      abi=1
      time=reaper.time_precise()
      repeat
          local tr=reaper.GetTrack(0,abi-1)
          reaper.SetOnlyTrackSelected(tr) 
          --clear tracks volume envelope points
          local vol_env=reaper.GetTrackEnvelopeByName(tr,"Volume")
          if not vol_env then
             reaper.Main_OnCommand(40406,0)--show track's volume envelope
             vol_env=reaper.GetTrackEnvelopeByName(tr,"Volume")
             reaper.Main_OnCommand(40406,0)--show track's volume envelope
          end
          reaper.DeleteEnvelopePointRange(vol_env,0,max)

          if reaper.GetMediaTrackInfo_Value(tr,"I_FOLDERDEPTH")==1 then
             cmd=reaper.NamedCommandLookup("_SWS_SELCHILDREN2")
             reaper.Main_OnCommand(cmd,0)--select all children track
          end
          
          if not reaper.GetParentTrack(tr) then
             --Move track's items
             reaper.Main_OnCommand(40421,0)--select all items in tracks
             local item=reaper.GetSelectedMediaItem(0,0)
             if item then
                P=reaper.GetMediaItemInfo_Value(item,"D_POSITION")
                reaper.ApplyNudge(0,0,0,1,first_measure-P,false,0)
                reaper.Main_OnCommand(40289,0)
             end
          end
          abi=abi+1
      until abi>reaper.CountTracks(0) or (reaper.time_precise()-time)>0.5
      reaper.SetOnlyTrackSelected(reaper.GetTrack(0,0))
  end
  
  --------------
  local function PlaytilDead(E,env)
    
    p=reaper.GetPlayPosition()
    
    if p>=E then
       reaper.Main_OnCommand(40044,0)--play/stop
       reaper.DeleteEnvelopePointRange(env,0,3600*24)
       RenewCueState()
    elseif reaper.GetPlayState()~=0 then
       reaper.defer(function() PlaytilDead(E,env) end)
    end
    
  end
  
  --------------
  local function AddPoints(env,time)
    -- GET THE ENVELOPE
      br_env = reaper.BR_EnvAlloc(env,false)
      active,visible,armed=reaper.BR_EnvGetProperties(br_env,true,true,true,true,0,0,0,0,0,0,true)
      if visible and armed then
         env_points_count=reaper.CountEnvelopePoints(env)
         if env_points_count>0 then
            for k=0,env_points_count+1 do 
                reaper.SetEnvelopePoint(env,k,nil,nil,nil,nil,false,true)
            end
         end
        
         -- IF THERE IS PREVIOUS POINT
         cursor_point = reaper.GetEnvelopePointByTime(env,time)
         if cursor_point~=-1 then
            --GET POINT VALUE
            _,valueOut,_,_,_= reaper.Envelope_Evaluate(env,time,0,0)
            -- ADD POINTS ON LOOP START AND END
            reaper.InsertEnvelopePoint(env,time,valueOut,2,0,false,true) -- INSERT startLoop point
            reaper.BR_EnvFree(br_env,0)
         end -- ENDIF there is a previous point
      end
  end 
  
  --------------
  local function Esc()
      
      reaper.Undo_BeginBlock()
      reaper.PreventUIRefresh(1)
      fadeout=1
      A=reaper.GetPlayPosition()
      
      --clear master point
      reaper.Main_OnCommand(40075,0)--tootle show master track
      master=reaper.GetMasterTrack()
      reaper.SetOnlyTrackSelected(master)
      reaper.Main_OnCommand(40406,0)--show volume envelope
      vol_env=reaper.GetTrackEnvelopeByName(master,"Volume")
      reaper.DeleteEnvelopePointRange(vol_env,0,reaper.GetProjectLength(0))
      reaper.Main_OnCommand(40406,0)--hide volume envelope
      reaper.Main_OnCommand(40075,0)--hide master track

      if reaper.GetPlayState()==1 then
         AddPoints(vol_env,A)
         reaper.InsertEnvelopePoint(vol_env,A+fadeout,0,2,0,false,true)
         reaper.Envelope_SortPoints(vol_env)
         PlaytilDead(A+fadeout,vol_env)
      else
         RenewCueState()
      end
      reaper.PreventUIRefresh(-1)
      reaper.Undo_EndBlock("Exit Run Show and back to preset",-1)
  end
  
  -----------------
  Esc()
  reaper.defer(function()end)

