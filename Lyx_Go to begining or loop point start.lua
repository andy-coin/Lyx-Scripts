
  local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
  
  --------------
  local function GetFirstItemPos()
      
      min=reaper.GetProjectLength(0)
      
      for abi=1,reaper.CountTracks(0) do
          tr=reaper.GetTrack(0,abi-1)
          for abii=1,reaper.CountTrackMediaItems(tr) do
              it=reaper.GetTrackMediaItem(tr,abii-1)
              if  api.giv(it,"B_FIXEDLANE_HIDDEN")==0 then
                  S=reaper.GetMediaItemInfo_Value(it,"D_POSITION")
                  min=(min>S and S) or min
                  break
              end
          end
      end
      
      return min
  end
  
  --------------
  local function main()
      
      local P=reaper.GetCursorPosition()
      
      for i = 1, reaper.CountProjectMarkers(0) do
          retval, is_region, pos, region_end, name, index = reaper.EnumProjectMarkers2(0,i-1)
          if  name == "=START" then
              m = pos
              break
          end
      end
      if not m then
         m = GetFirstItemPos()
      end
      
      starttime,endtime=reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
      
      if  starttime==endtime then
      
          position = ( (reaper.GetPlayState()==0 and P==m) and 0 ) or m
           
          reaper.SetEditCurPos(position,true,true)
      else
         reaper.SetEditCurPos(starttime,true,true) 
      end
      
  end
  
  reaper.defer(main)
  
  if  api.load('practice mode','snapshot') == '1' then
      api.cmd(api.name('_SWSSNAPSHOT_GET1'),0)
      snapshot_window = api.name('_SWSSNAPSHOT_OPEN')
      if  reaper.GetToggleCommandState(snapshot_window)==0 then
          api.cmd(snapshot_window,0)
      end
  end
