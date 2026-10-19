    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    local function main()

        if api.cst(0) == 0 then return end

        api.ubb()

        trackz = r.SaveTracks()
        
        REC = {}
        
        api.cmd(40062,0)--duplicate
        
        for abi=1,#trackz do
            tr=trackz[abi]
            REC[abi] = api.gtv(tr,"I_RECARM")
            api.stv(tr,"I_RECARM",0)
            api.stv(tr,"I_RECMON",0)
            api.stv(tr,"B_SOLO_DEFEAT",0)
        end
        
        api.cmd(api.name('_SWS_SELCHILDREN2'),0)
        api.cmd(api.name('_SWS_DELALLITEMS'),0)
        api.cmd(42796,0)--Track lanes: Delete all lanes (including media items)
        api.cmd(api.name('_S&M_REMOVE_ALLENVS'),0)
        
        api.ueb(0,"Duplicate track without item",0)
        
    end
    
    main()
