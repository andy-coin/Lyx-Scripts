
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    --quit=reaper.NamedCommandLookup("_RS8820612feb625326318c52f7878a498c5fc738ea")
    --reaper.Main_OnCommand((r.CountProjects()>1 and 40860) or quit,0)
    
    api.cmd(40860,0)
    reaper.defer(function()end)
