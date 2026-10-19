    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    reaper.BR_GetMouseCursorContext()
    
    item=reaper.BR_GetMouseCursorContext_Item()
    
     if  item then
        
        tr = api.git(item)
        selected=reaper.IsMediaItemSelected(item)
        
        api.sis(item,selected)
        api.sts(tr,selected)
         
        api.ua()
        
    end
    
    
    --api.cmd((item_group and 1156) or 0,0)
    
    --[[trackzzz=r.SaveTracks()

    reaper.BR_GetMouseCursorContext()
    local tr = reaper.BR_GetMouseCursorContext_Track()

    r.RestoreTracks(trackzzz)
    if  tr then
        api.sts(tr,not reaper.IsTrackSelected(tr))
    end--]]

    reaper.defer(function()end)
