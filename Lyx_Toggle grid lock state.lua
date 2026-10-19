
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    -----Thank Feed The Cat Script-----
    fixed  = r.ScriptID("FTC Tools/Adaptive grid/Set grid to fixed (adaptive).lua")
    medium = r.ScriptID("FTC Tools/Adaptive grid/Set grid to medium (adaptive).lua")
    wild   = r.ScriptID("FTC Tools/Adaptive grid/Set grid to wide (adaptive).lua")
    narrow = r.ScriptID("FTC Tools/Adaptive grid/Set grid to narrow (adaptive).lua")
    
    local function main()
        
        local lock = (api.load("Grid",'Grid lock') == "1" and 0) or 1
        local state = (lock == 1 and " [ Lock ] ") or " [ UnLock ] "
        api.save("Grid",'Grid lock',lock,false)
        r.billboard("Set grid auto-change"..state)
        
        if  lock == 0 then
            r.AdjustGrid()
            --api.cmd(api.name(medium),0)
        else
            api.cmd(api.name(fixed),0)
        end
        
        action = select(4, reaper.get_action_context()) -- this script's own id, on any machine
        reaper.SetToggleCommandState(0,action,lock)
        reaper.RefreshToolbar2(0,action)
    end

    main()

    reaper.defer(function()end)
