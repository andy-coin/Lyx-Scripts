  
  r=reaper
  
  local function main()
    
    if reaper.CountSelectedTracks(0)~=1 then return end
    
    tr=reaper.GetSelectedTrack(0,0)
    parent=reaper.GetParentTrack(tr)
    
    if not parent then
       mom=tr
    else
       mom=parent
    end
    
    local mode=reaper.GetMediaTrackInfo_Value(mom,"I_RECMODE") 
    
    if mode~=7 and mode~=8 then return end
    
    reaper.SetOnlyTrackSelected(mom)
    cmd = reaper.NamedCommandLookup("_RS2b7916dcaba757d714942f43e6d02e9370568325")
    reaper.Main_OnCommand(cmd,0)-- Insert MIDI track
    
    local child = reaper.GetSelectedTrack(0,0)
    
    if reaper.GetMediaTrackInfo_Value(mom,"I_FOLDERDEPTH")==0 then
       reaper.SetMediaTrackInfo_Value(mom,"I_FOLDERDEPTH",1)
       reaper.SetMediaTrackInfo_Value(child,"I_FOLDERDEPTH",-1) 
    end
    
    reaper.SetMediaTrackInfo_Value(child, "B_MAINSEND", 0)
    local send = reaper.CreateTrackSend(child, mom)
    reaper.SetTrackSendInfo_Value(child, 0, send, "D_VOL", 1)
    reaper.SetTrackSendInfo_Value(child, 0, send, "I_SENDMODE", 0)
    reaper.SetOnlyTrackSelected(child)
  end
  
  reaper.Undo_BeginBlock()
  main()
  reaper.Undo_EndBlock("Create child midi track",-1)
    
