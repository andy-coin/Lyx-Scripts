    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r = require("_lib._Lyx_HOME")

    ------------
    ---CUSTOM---
    ------------

    function main()
        
        local item_group = reaper.GetToggleCommandState(1156) == 1
        local snap = reaper.GetToggleCommandState(1157) == 1
        local window,segment,detail = api.mcw()
        local mouse = api.mcp()
        local cursor = (snap and reaper.SnapToGrid(0,mouse)) or mouse
        
        api.cmd(41110,0) --select track under mouse
        api.cmd(40528,0) --sel ect items under mouse cursor

        if  item_group then api.cmd(40034,0) end --select items in group        
        if  snap and api.gps(0) == 0 then api.sec(cursor,false,false) end
        if auto_change_fx_window and api.mcw() == 'tcp' then r.SwitchFxWindow(api.gst(0,0)) end

        api.ua()
    end
    
    r.SwitchFxWindow(api.gst(0,0))
    --main()
    reaper.defer(function()end)
