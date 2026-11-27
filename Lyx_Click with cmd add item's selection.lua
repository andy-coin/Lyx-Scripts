    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    item=api.mci()
    
     if  item then
        
        tr = api.git(item)
        selected=reaper.IsMediaItemSelected(item)
        
        api.sis(item,selected)
        api.sts(tr,selected)
         
        api.ua()
        
    end
    
    
    --api.cmd((item_group and 1156) or 0,0)
    
    --[[trackzzz=r.SaveTracks()

    local tr = api.mct()

    r.RestoreTracks(trackzzz)
    if  tr then
        api.sts(tr,not reaper.IsTrackSelected(tr))
    end--]]

    reaper.defer(function()end)
