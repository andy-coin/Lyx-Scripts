
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    window,segment,detail = reaper.BR_GetMouseCursorContext()
    item=reaper.BR_GetMouseCursorContext_Item()
    if  segment == 'envelope' then
        return 
    elseif  item then
        
        api.cmd(40289,0)
        tr = api.git(item)
        api.cmd(40297,0)
        api.cmd(api.name("_SWS_UNSELMASTER"),0)
        
        api.sis(item,true)
        if  reaper.GetToggleCommandState(1156)==1 then
            api.cmd(40034,0)--select items in group
        end
        api.sts(tr,true)
        
        api.ua()
        
    end

    reaper.defer(function()end)
