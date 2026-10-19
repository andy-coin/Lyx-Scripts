  
  r=reaper
  
  --i=fade in(second,curve,direction) --0 for cut in
  --o=fade out(second,curve,direction)--0 for cut out
  
  --W=prewait(second)
  --w=postwait(second)

  --V=volume in  trim(dB,second)
  --v=volume out trim(dB,second)

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
  local function dB_Value(dB)
      return reaper.ScaleToEnvelopeMode(1,10^(dB/20))
  end

  --------------
  local function DVOL_to_dB(dvol)
    if dvol == 0 then
      return -math.huge -- -∞ dB
    else
      return 20*math.log(dvol,10)
    end
  end

  --------------
  local function dB_to_DVOL(dB)
      return 10^(dB/20)
  end

  --------------
  local function AddPoints(env,pt1,pt2,pv2)
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
         --reaper.DeleteEnvelopePointEx(TrackEnvelope envelope, integer autoitem_idx, integer ptidx)
         old_point = reaper.GetEnvelopePointByTime(env,pt1)
         if old_point~=-1 then
            --GET POINT VALUE
            _,valueOut,_,_,_= reaper.Envelope_Evaluate(env,pt1,0,0)
            -- ADD POINTS ON LOOP START AND END
            reaper.InsertEnvelopePoint(env,pt1,valueOut,2,0,false,true) -- INSERT startLoop point
         end -- END IF there is a previous point
         reaper.DeleteEnvelopePointRange(vol_env,0,pt1-0.001)
         reaper.InsertEnvelopePoint(env,pt2,pv2,2,0,false,true) 
         reaper.DeleteEnvelopePointRange(env,pt2+0.001,max)
         reaper.BR_EnvFree(br_env,0)
         reaper.Envelope_SortPoints(env)
         
      end
  end
  
  --------------
  local function Go()
      
      if reaper.CountSelectedTracks(0)>1 then return end

      tr=reaper.GetSelectedTrack(0,0)
      max=3600*12--sec
      min=0.005--sec

      if not tr then return end
      
      if reaper.GetToggleCommandState(1068)==1 then
         reaper.Main_OnCommand(1068,0)
      end

      if reaper.GetPlayState()==0 then 
         reaper.SetEditCurPos(GetSetProjectStart(),false,false)
         reaper.Main_OnCommand(1007,0) --play 
         reaper.Main_OnCommand(40341,0)--mute all tracks
      end

      A=reaper.GetPlayPosition()+min*10

      if reaper.GetMediaTrackInfo_Value(tr,"I_FOLDERDEPTH")==1 then
         cmd=reaper.NamedCommandLookup("_SWS_SELCHILDREN2")
         reaper.Main_OnCommand(cmd,0)--select all children track
      end
      reaper.Main_OnCommand(40421,0)--select all items in tracks
      reaper.SetOnlyTrackSelected(tr)
      
      offset=0
      
      ::Beginning::

      count=count+1
--reaper.ShowConsoleMsg(count.."\n")
      IDX=reaper.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER")    
      reaper.SetMediaTrackInfo_Value(tr,"B_MUTE",0)

      _,name=reaper.GetSetMediaTrackInfo_String(tr,"P_NAME","",false)
      i=name:match("i%(([%-%.%d,]+)%)")
      o=name:match("o%(([%-%.%d,]+)%)")
      V=name:match("V%(([%-%.%d,]+)%)")
      v=name:match("v%(([%-%.%d,]+)%)")
      W=name:match("W%(([%-%.%d,]+)%)")
      w=name:match("w%(([%-%.%d,]+)%)")
      
      abi=2
      time=reaper.time_precise()
      repeat
            last=reaper.GetTrack(0,IDX-abi)
            if not last or reaper.CountTrackMediaItems(last)>0 then break end
            abi=abi+1
      until (reaper.time_precise()-time)>0.5
      idx=tonumber(name:match("{(%d+)}"))
      if idx and idx>0 and idx<IDX then last=reaper.GetTrack(0,idx-1) end
      if not last then goto CURRENT_TRACK end 

      --reaper.SetMediaTrackInfo_Value(last,"B_MUTE",0)

      ::postwait::
      wait=0
      if w then
         value=w:gmatch("(%-?%d*%.?%d*)")
         wait=value()
         wait=tonumber(wait)
         if type(wait)~="number" or wait<0 then wait=0 end 
--reaper.ShowConsoleMsg("postwait="..w.."\n")
      end
      
      vol_env=reaper.GetTrackEnvelopeByName(last,"Volume")
      if not vol_env then
        reaper.SetOnlyTrackSelected(last)
        reaper.Main_OnCommand(40406,0)-- show volume envelope
        vol_env = reaper.GetTrackEnvelopeByName(last,"Volume")
        reaper.Main_OnCommand(40406,0)-- hide volume envelope
        reaper.SetOnlyTrackSelected(tr)
      end
      
      ::volume_change::
      if v then 
         value=v:gmatch("(%-?%d*%.?%d*),?")
         dB=value()
         dB=tonumber(dB)
         if type(dB)~="number" then goto out end
         if dB<=-99 then dB=-math.huge end
         if dB>12 then dB=12 end
         sec=value()
         sec=tonumber(sec)
         if type(sec)~="number" or sec<min then sec=min end
         
         AddPoints(vol_env,A+wait,A+wait+sec,dB_Value(dB))
         
--reaper.ShowConsoleMsg("volume trim="..v.."\n")
      end
      
      ::out::
      if o then 
         value=o:gmatch("(%-?%d*%.?%d*),?")
         sec=tonumber(value())
         if type(sec)~="number" or sec<min then sec=min end
         cur=value()
         cur=tonumber(cur)
         if type(cur)~="number" then cur=2 elseif cur>5 or cur<0 then cur=2 end
         if cur==5 then
            dir=value()
            if type(dir)~="number" then dir=0 end
            dir=math.max(math.min(dir,1),-1)
         else
            dir=0
         end
         
         AddPoints(vol_env,A+wait,A+wait+sec,0)
--reaper.ShowConsoleMsg("out="..o.."\n")
      end
      
------------------------------------------------------------------------------
-------------------------------CURRENT TRACK----------------------------------
------------------------------------------------------------------------------

      ::CURRENT_TRACK::
      first=reaper.GetTrackMediaItem(tr,0) or reaper.GetSelectedMediaItem(0,0)
      if first then 
         starttime=reaper.GetMediaItemInfo_Value(first,"D_POSITION")-min
      else
         starttime=0
      end


      ::PREWAIT::
      WAIT=0
      if W and ABIGEL and first then 
         value=W:gmatch("(%-?%d*%.?%d*)")
         WAIT=value()
         WAIT=tonumber(WAIT)
         if type(WAIT)~="number" or WAIT<0 then WAIT=0 end 
--reaper.ShowConsoleMsg("prewait="..W.."\n")
      end
      
      offset=starttime-A

      vol_env=reaper.GetTrackEnvelopeByName(tr,"Volume")
      if not vol_env then
         reaper.Main_OnCommand(40406,0)-- show volume envelope
         vol_env = reaper.GetTrackEnvelopeByName(tr,"Volume")
         reaper.Main_OnCommand(40406,0)-- show volume envelope
      end

      ::IN::
      if i and ABIGEL and first then
         value=i:gmatch("(%-?%d*%.?%d*),?")
         sec=value()
         sec=tonumber(sec)
         if type(sec)~="number" or sec<min then sec=min else sec=math.max(0,sec) end
         
         cur=value()
         cur=tonumber(cur)
         if type(cur)~="number" then cur=2 elseif cur>5 or cur<0 then cur=2 end
         if cur==5 then
            dir=value()
            if type(dir)~="number" then dir=0 end
            dir=math.max(math.min(dir,1),-1)
         else
            dir=0
         end
         --_,_,value,_,_=reaper.GetEnvelopePoint(vol_env,reaper.GetEnvelopePointByTimeEx(vol_env,-1,A))
         reaper.InsertEnvelopePoint(vol_env,A+WAIT+offset,0,cur,dir,false,true)
         reaper.InsertEnvelopePoint(vol_env,A+WAIT+offset+sec,dB_Value(0),cur,dir,false,true) 
         reaper.Envelope_SortPoints(vol_env)
--reaper.ShowConsoleMsg("in="..i.."\n")
      end 
      
      ::VOLUME_CHANGE::
      if V and ABIGEL and first then 
         value=V:gmatch("(%-?%d*%.?%d*),?")
         dB=value()
         dB=tonumber(dB)
         if type(dB)~="number" then goto FOLDER end
         if dB<=-99 then dB=-math.huge end
         if dB>12 then dB=12 end
         sec=value()
         sec=tonumber(sec)
         if type(sec)~="number" or sec<min then sec=min end

         AddPoints(vol_env,A+WAIT+offset,A+WAIT+offset+sec,dB_Value(dB))
--reaper.ShowConsoleMsg("VOLUME TRIM="..V.."\n")
      end

      ::FOLDER::
      parent=reaper.GetParentTrack(tr)
      if parent then
         reaper.SetMediaTrackInfo_Value(parent,"B_MUTE",0)
         reaper.SetOnlyTrackSelected(tr)
         reaper.Main_OnCommand(40421,0)--select all items in tracks
         if reaper.GetMediaTrackInfo_Value(tr,"I_FOLDERDEPTH")<0 then goto NEXT_CUE end
         tr=reaper.GetTrack(0,IDX)
         goto Beginning    
      elseif not ABIGEL then
         ABIGEL=true
         reaper.ApplyNudge(0,0,0,1,A-starttime,false,0)       
         reaper.Main_OnCommand(40688,0)--lock item 
         reaper.UpdateArrange()  
         goto CURRENT_TRACK
      elseif reaper.GetMediaTrackInfo_Value(tr,"I_FOLDERDEPTH")==1 then 
         tr=reaper.GetTrack(0,IDX)
         goto Beginning 
      end

      ::NEXT_CUE::

      reaper.Main_OnCommand(40289,0)
      next=reaper.GetTrack(0,IDX)
      if next then
         reaper.SetOnlyTrackSelected(next)
      else 
         reaper.Main_OnCommand(40297,0)--unselect all tracks
      end  
      
      reaper.UpdateArrange()
      reaper.UpdateTimeline()
      
  end
  
  reaper.ClearConsole()
  TIME=reaper.time_precise()
  count=0
  reaper.defer(Go)
  --reaper.ShowConsoleMsg(string.format("%.6f",(reaper.time_precise()-TIME)))
