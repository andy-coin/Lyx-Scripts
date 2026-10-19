  
  r=reaper
  play=reaper.GetPlayState()
  
  if play==1 or play==5 then  return end
  
  reaper.Main_OnCommand(42440,0)--Dry run master
  
  if true then return end
  
  master=reaper.GetMasterTrack(0)
  master=reaper.GetMediaTrackInfo_Value(master,"I_SELECTED")
  it_n=reaper.CountSelectedMediaItems(0)
  tr_n=reaper.CountSelectedTracks(0)
  Start,End=reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
  window,seg,detial=reaper.BR_GetMouseCursorContext()
  
  if master==0 and it_n==0 and tr_n==0 and Start==End then return end
  
  if Start~=End then
       if master==1 or tr_n==1 and it_n==0 and window~="tcp" and window~="mcp" then
          reaper.Main_OnCommand(42441,0)--Dry run master in time selection
       elseif tr_n>0 and detial~="item" and detial~="item_stretch_marker" or it_n==0 then
          reaper.Main_OnCommand(42439,0)--Dry run selected tracks in time selection
       elseif it_n>1 or detial=="item" or detial=="item_stretch_marker" or tr_n==0 then
          reaper.Main_OnCommand(42437,0)--Dry run selected items including take/track FX and settings
       end
  elseif master==1 or tr_n==1 and it_n==0 and window~="tcp" and window~="mcp" then
     reaper.Main_OnCommand(42440,0)--Dry run master
  elseif tr_n>0 and detial~="item" and detial~="item_stretch_marker" or it_n==0 then
     reaper.Main_OnCommand(42438,0)--Dry run selected tracks
  elseif it_n>1 or detial=="item" or detial=="item_stretch_marker" or tr_n==0 then
     reaper.Main_OnCommand(42437,0)--Dry run selected items including take/track FX and settings
  end
  
  
  reaper.defer(function() end)
