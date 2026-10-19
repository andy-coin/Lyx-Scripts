    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    --------------
    local function main()
        
        local distence,it_n,P1,P2
        
        r.SelItemFilter()
        
        if it_n == 0 then return end
        
        api.cmd(api.name('_SWS_SAVEVIEW'),0)
        
        P1 = api.gec()
        
        api.cmd(41174,0)--Item navigation: Move cursor to end of items
        
        P2 = api.gec()
        
        it_n = api.csi(0)
        
        distence = P1 - P2

        for abi=1,api.csi(0) do
            local item = api.gsi(0,abi-1)
            local p    = api.giv(item,"D_POSITION")
            api.siv(item,'D_POSITION',p+distence)
        end
        
        api.sec(P1,false,false)

        api.cmd(api.name('_SWS_RESTOREVIEW'),0)
        
    end
    
    main()
