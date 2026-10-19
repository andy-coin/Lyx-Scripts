  
  local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
  --script_path=script_path:gsub("/MIDI Editor","")
  package.path = package.path..";"..script_path.."?.lua"
  local r=require("_Lyx_HOME")
   
  --------------
  local function GetProjectLength()
      
      min=reaper.GetProjectLength(0)
      max=min
      
      for abi=1,reaper.CountTracks(0) do
          tr=reaper.GetTrack(0,abi-1)
          it=reaper.GetTrackMediaItem(tr,0)
          if it and reaper.GetMediaItemInfo_Value(it,"B_MUTE")==0 then
             S=reaper.GetMediaItemInfo_Value(it,"D_POSITION")
             if min>S then
                min=S
             end
          end
      end
      
      return min,max
  end
  
  --os.execute('pkill -x "Google Drive" ')
  --os.execute('open -a "MonitorControl" ')
  
  name=reaper.GetProjectName()
  
  if name=="" then goto END end
  
  name=name:gsub('.RPP','')
  name=name:gsub('.rpp','')
  
  last_preview_point=reaper.GetExtState("Project Changes",name)
  last_movement=reaper.GetExtState("Project Movements",name)
  if last_movement=='' then last_movement=reaper.GetProjectStateChangeCount(0) end
  if last_preview_point=='' then 
     last_preview_point=reaper.GetProjectStateChangeCount(0)
  end
  last_preview_point=last_preview_point+reaper.GetProjectStateChangeCount(0)-last_movement
  
  if name~="" and reaper.CountMediaItems(0)>1 and math.abs(last_preview_point)>=30000 and reaper.GetPlayState()==0 then
      
     reaper.SetExtState("Project Changes",name,0,true)
     
     reaper.GetSetProjectInfo_String(0, 'RENDER_PATTERN', name, true)
     pr_path = reaper.GetProjectPathEx( 0, '' )
     reaper.GetSetProjectInfo_String(0, 'RENDER_FILE', pr_path, true)
     file=pr_path:gsub(' ','\\ ')..'/'..name:gsub(' ','\\ ')..'.wav'
     --reaper.ShowConsoleMsg(file.."\n")
     os.execute('rm '..file)
     
     if 7==reaper.ShowMessageBox("This project seems change a lot after last preview file was saved","Update project's preview file? >_<",4) then 
        goto END
     end           
     bounds_setting=reaper.GetSetProjectInfo(0, 'RENDER_SETTINGS',0,false)
     reaper.GetSetProjectInfo(0, 'RENDER_SETTINGS',0,true)
     bounds_flag=reaper.GetSetProjectInfo(0, 'RENDER_BOUNDSFLAG',0,false)
     reaper.GetSetProjectInfo(0, 'RENDER_BOUNDSFLAG', 2, true)
     loop=reaper.GetToggleCommandState(1068)
     Start,End = reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
     min,max=GetProjectLength()
     reaper.GetSet_LoopTimeRange2(0,true,loop,min,max,false)
     reaper.Main_OnCommand(42230,0)--render
     reaper.GetSet_LoopTimeRange2(0,true,loop,Start,End,false)
     desktopPath=os.getenv("HOME")..'/Desktop'
     reaper.GetSetProjectInfo(0,'RENDER_SETTINGS',bounds_setting, true)
     reaper.GetSetProjectInfo_String(0,'RENDER_FILE',desktopPath, true)
     reaper.GetSetProjectInfo(0,'RENDER_BOUNDSFLAG' ,bounds_flag, true)--]]
  end 
  
  reaper.SetExtState("Project Changes",name,last_preview_point,true)
  
  ::END::
  reaper.SetExtState("Project Movements",name,reaper.GetProjectStateChangeCount(0),true)
  
  ori_color = api.load('timeline','color')
  
  ori_color = (ori_color ~= '' and ori_color) or 16757568
  
  reaper.SetThemeColor("col_tl_bgsel2",ori_color,0)
  reaper.UpdateTimeline()
  
  reaper.Main_OnCommand(40004,0)--quit REAPER
