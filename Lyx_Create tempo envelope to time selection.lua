
  local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  --------------
  local function prompt(start)
      
      ori_timesig_num,ori_timesig_demon,tempo=reaper.TimeMap_GetTimeSigAtTime(0,start)
      if tempo%1==0 then
         tempo=math.floor(tempo)
      end
      
      local default_bpm = tempo
      local default_time_Sig = ori_timesig_num.."/"..ori_timesig_demon
      local default_point_Division = "1/2"
    
      local ok, csv = r.GetUserInputs("Create tempo envelope points to time selection",3,
        "BPM:,Time Signature:,Point Density:, extrawidth=100",
        default_bpm..','..default_time_Sig..','..default_point_Division)
        
      if not ok then return end
      --reaper.ShowConsoleMsg(csv)
      local bpm,timeSig,pointDiv = csv:match("^(.*),(.*),(.*)$")
      
      timeSig_num=timeSig:match("%d+")
      timeSig_demon=timeSig:gsub(timeSig_num.."/","")
      --reaper.ShowConsoleMsg(timeSig_num.."|"..timeSig_demon)
      
      if pointDiv=="4" then 
          pointDiv=0.0625
      elseif pointDiv=="2" then
          pointDiv=0.125
      elseif pointDiv=="1" then
          pointDiv=0.25
      elseif pointDiv=="1/2" then
          pointDiv=0.5
      elseif pointDiv=="1/4" then
          pointDiv=1
      elseif pointDiv=="1/8" then
          pointDiv=2
      elseif pointDiv=="1/16" then
          pointDiv=4
      elseif pointDiv=="1/32" then
          pointDiv=8
      elseif pointDiv=="1/64" then
          pointDiv=16
      elseif pointDiv=="1/128" then
          pointDiv=32
      elseif pointDiv=="0" then
          pointDiv=0
      else
          return 
      end
      pointDiv=pointDiv*timeSig_num/timeSig_demon
      return tonumber(bpm),tonumber(timeSig_num),tonumber(timeSig_demon),pointDiv
  end
  
  --------------
  local function main()
      
      starttime,endtime = reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)

      if starttime==endtime and reaper.CountSelectedMediaItems(0)==0 then return end
      
      bpm,num,demon,div=prompt(starttime)
      
      if not bpm then return end
      
      r.Undo("Create tempo envelope points to time selection", function()
          if starttime==endtime then
             reaper.Main_OnCommand(41039,0)
             starttime,endtime = reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
             reaper.Main_OnCommand(40020,0)
          end

          reaper.PreventUIRefresh(1)
          P=reaper.GetCursorPosition()

          if 0==reaper.GetToggleCommandState(41050) then
             --reaper.Main_OnCommand(41050,0)
          end

          master=reaper.GetMasterTrack(0)
          Env=reaper.GetTrackEnvelopeByName(master,"Tempo map")
          CBperM,CSig_D,CBPM=reaper.TimeMap_GetTimeSigAtTime(0,starttime-0.00000001)
          reaper.SetTempoTimeSigMarker(0,-1,starttime,-1,-1,CBPM,CBperM,CSig_D,false)
          reaper.DeleteEnvelopePointRange(Env,starttime,endtime)

          if div~=0 then 

             BperM,Sig_D,BPM=reaper.TimeMap_GetTimeSigAtTime(0,starttime)

             reaper.SetEditCurPos(starttime,false,false)
             if num==BperM and demon==Sig_D then
                reaper.SetCurrentBPM(0,bpm,true)
                reaper.Main_OnCommand(42330,0)
             else
                reaper.SetTempoTimeSigMarker(0,-1,starttime,-1,-1,bpm,num,demon,false)
             end
             step=60/bpm/div*num/4
             times=(endtime-starttime)/step

             for abi=1,times do
                 reaper.SetEditCurPos(starttime+abi*step,false,false)
                 reaper.Main_OnCommand(42330,0)
                 lasttime=starttime+abi*step
             end

             reaper.SetTempoTimeSigMarker(0,-1,lasttime,-1,-1,CBPM,CBperM,CSig_D,false)
             reaper.SetEditCurPos(P,false,false)
          end

          reaper.PreventUIRefresh(-1)
          reaper.UpdateArrange()
      end)
  end
  
  r.run(main)
 
  
