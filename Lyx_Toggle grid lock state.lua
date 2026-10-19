
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    -----Thank Feed The Cat Script-----
    fixed  = '_RSd4c23469a25528b9075743ce7e7baf5e5c9edeaa'
    medium = '_RS18326a165ec53a69aedced71d97a0f95715a0a8a'
    wild   = '_RS8156a582bcab3d91af2bb026e78690e99f4464da'
    narrow = '_RSf612c71a2852e9cc682dbec04707f9e452448d6f'
    
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
        
        action = api.name("_RS38780eecd3f2b5c03c9ef9ba7a1276af5b275f82")
        reaper.SetToggleCommandState(0,action,lock)
        reaper.RefreshToolbar2(0,action)
    end

    main()

    reaper.defer(function()end)
