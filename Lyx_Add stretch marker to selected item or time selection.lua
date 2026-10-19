  
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  --------------
  local function GetItemsInRange(track, areaStart, areaEnd)
      local items = {}
      local itemCount = reaper.CountTrackMediaItems(track)
      for k = 0, itemCount - 1 do 
          local item = reaper.GetTrackMediaItem(track, k)
          local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          local itemEndPos = pos+length
  
          --check if item is in area bounds
          if (itemEndPos > areaStart and itemEndPos <= areaEnd) or
              (pos >= areaStart and pos < areaEnd) or
              (pos <= areaStart and itemEndPos >= areaEnd) then
                  table.insert(items,item)
          end
      end
      for abi=1,#items do
          reaper.SetMediaItemSelected(items[abi],true)
      end
      return items
  end
  
  --------------
  local function GetRazorEdits()
      local trackCount = reaper.CountTracks(0)
      local min=reaper.GetProjectLength(0)
      local max=0
      local razor=false
      for i = 0, trackCount - 1 do
          local track = reaper.GetTrack(0, i)
          local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
          if area ~= '' then
              razor=true
              --PARSE STRING
              local str = {}
              for j in string.gmatch(area, "%S+") do
                  table.insert(str, j)
              end
              
              --FILL AREA DATA
              local j = 1
              while j <= #str do
                  --area data
                  local areaStart = tonumber(str[j])
                  local areaEnd = tonumber(str[j+1])
                  local GUID = str[j+2]
                  local isEnvelope = GUID ~= '""'
                  --get item/envelope data
                  local items = {}
                  local envelopeName, envelope
                  local envelopePoints
                  
                  if not isEnvelope then
                      items = GetItemsInRange(track, areaStart, areaEnd)
                  end
                  
                  if min>areaStart then
                     min=areaStart
                  end
                  if max<areaEnd then
                     max=areaEnd
                  end
                  j = j + 3
              end
              reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', true)
          end
      end
      return razor,min,max
  end
    
  --------------
  local function prompt(start)
      
      ori_timesig_num,ori_timesig_denom,tempo=reaper.TimeMap_GetTimeSigAtTime(0,start)
      if tempo%1==0 then
         tempo=math.floor(tempo)
      end
      
      local default_bpm = tempo
      local default_time_Sig = ori_timesig_num.."/"..ori_timesig_denom
      local default_point_Division = "1/8"
    
      local ok, csv = r.GetUserInputs("Creating stretch marker...",3,
        "  Marker Density:,  BPM:,  Time Signature:, extrawidth=0",
        default_point_Division..","..default_bpm..','..default_time_Sig)
        
      if not ok then return end
      --reaper.ShowConsoleMsg(csv)
      local pointDiv,bpm,timeSig = csv:match("^(.*),(.*),(.*)$")
      
      timeSig_num=timeSig:match("%d+")
      timeSig_demon=timeSig:gsub(timeSig_num.."/","")
      --reaper.ShowConsoleMsg(timeSig_num.."|"..timeSig_demon)
      
      if pointDiv=="1" then
          pointDiv=0.25
      elseif pointDiv=="2/3" then
          pointDiv=0.3333333333
      elseif pointDiv=="1/2" then
          pointDiv=0.5
      elseif pointDiv=="1/3" or pointDiv=="3" then
          pointDiv=0.6666666666
      elseif pointDiv=="1/4" or pointDiv=="4" then
          pointDiv=1
      elseif pointDiv=="1/6" or pointDiv=="6" then
          pointDiv=1.3333333333
      elseif pointDiv=="1/8" or pointDiv=="8" then
          pointDiv=2
      elseif pointDiv=="1/12" or pointDiv=="12" then
          pointDiv=2.6666666666
      elseif pointDiv=="1/16" or pointDiv=="16" then
          pointDiv=4
      elseif pointDiv=="1/24" or pointDiv=="24" then
          pointDiv=5.3333333333
      elseif pointDiv=="1/32" or pointDiv=="32" then
          pointDiv=8
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
      
      razor,starttime,endtime=GetRazorEdits()
      if not razor then
         starttime,endtime = reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
         if starttime~=endtime then 
            time_selection=true
         elseif reaper.CountSelectedMediaItems(0)==0 then
            return 
         end
      end
      
      bpm,num,demon,div=prompt(starttime)
      
      if not bpm then return end
      
      r.Undo("Add stretch markers", function()
          if not razor and not time_selection then
             reaper.Main_OnCommand(41039,0)
             starttime,endtime = reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
             reaper.Main_OnCommand(40020,0)
          end

          reaper.PreventUIRefresh(1)
          P=reaper.GetCursorPosition()

          s,e = reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
          if s==e then
             reaper.GetSet_LoopTimeRange2(0,true,false,starttime,endtime,false)
             reaper.Main_OnCommand(41845,0)
             reaper.GetSet_LoopTimeRange2(0,true,false,0,0,false)
          else
             reaper.Main_OnCommand(41845,0)
          end

          if div~=0 then 

             BperM,Sig_D,BPM=reaper.TimeMap_GetTimeSigAtTime(0,starttime)

             reaper.SetEditCurPos(starttime,false,false)
             if num==BperM and demon==Sig_D then
                reaper.Main_OnCommand(41842,0)
             else
                reaper.SetTempoTimeSigMarker(0,-1,starttime,-1,-1,bpm,num,demon,false)
                reaper.Main_OnCommand(41842,0)
             end

             step=60/bpm/div*num/4
             times=(endtime-starttime)/step

             for abi=1,times do
                 reaper.SetEditCurPos((starttime+abi*step)-0.005,false,false)
                 reaper.Main_OnCommand(41842,0)
                 lasttime=starttime+abi*step
             end

             if lasttime and (num~=BperM or demon~=Sig_D) then -- restore the signature that was there before
                reaper.SetTempoTimeSigMarker(0,-1,lasttime,-1,-1,BPM,BperM,Sig_D,false)
             end
             reaper.SetEditCurPos(P,false,false)
          end

          reaper.PreventUIRefresh(-1)
          reaper.UpdateArrange()
      end)
  end
  
  r.run(main)
  
  
