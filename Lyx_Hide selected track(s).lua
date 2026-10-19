    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    local function main()
        
        local win = api.mcw()
        
        for abi=1,api.cst(0) do
            local tr = api.gst(0,abi-1)
            if  api.gtv(tr,'I_RECARM') ~= 0 and api.gtv(tr,'I_RECMON') ~= 0 then
                reaper.SetMediaTrackInfo_Value(tr,"I_RECMODE",2)
            end
            api.cmd(api.name('_SWS_SELCHILDREN2'),0) -- select children
            api.cmd(api.name('_SWSTL_HIDE'..((win == 'mcp' and 'MCP') or 'TCP')),0)
        end

        local tr = api.gst(0,api.cst(0)-1)
        
        while ( tr ~= api.gt(0,api.ct(0)-1) ) do
            api.cmd(api.name('_XENAKIOS_SELNEXTTRACK'),0) -- select next track
            tr = api.gst(0,0)
            if  api.itv(tr,false) then api.sot(tr) return end
        end
        
        while ( tr ~= api.gt(0,0) ) do
            api.cmd(api.name('_XENAKIOS_SELPREVTRACK'),0) -- select next track
            tr = api.gst(0,0)
            if  api.itv(tr,false) then api.sot(tr) return end
        end

    end
    
    api.ubb()
    main()
    api.ueb(0,'Hide select track(s)',-1)
