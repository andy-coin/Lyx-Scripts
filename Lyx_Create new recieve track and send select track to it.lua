    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
  
    -----CUSTOM-----
        default_icon = reaper.GetResourcePath()..'/Data/track_icons/Logic//Effects/fx.png' 

    
    if  api.cst(0) == 0 then return end

    reaper.Undo_BeginBlock()
    api.pur( 1 )
    
    --local idx = reaper.GetMediaTrackInfo_Value(, "IP_TRACKNUMBER")
    reaper.InsertTrackAtIndex(api.ct(0), true)
    local bus = api.gt(0,api.ct(0)-1)
    api.stv( bus, "I_CUSTOMCOLOR", 30759958)
    api.ts ( bus, "P_NAME", "RETURN", true )
    if  reaper.file_exists(default_icon) then api.ts ( bus, "P_ICON",default_icon,true) end
    
    -- Loop through all tracks in the project
    for abi=1,api.cst(0) do

        local tr = api.gst(0, abi-1)
        local send = reaper.CreateTrackSend(tr, bus)
        
        -- Make sure send is at unity, post-fader (overriding default send values)
        reaper.SetTrackSendInfo_Value(tr, 0, send, "D_VOL", 1)
        reaper.SetTrackSendInfo_Value(tr, 0, send, "I_SENDMODE", 0)    
    
    end
    
    
    api.pur(-1)
    
    reaper.TrackList_AdjustWindows( false )
    api.ua()
    
    reaper.Undo_EndBlock("Create return track and send selected tracks to it", -1)
