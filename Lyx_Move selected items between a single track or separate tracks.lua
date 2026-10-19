    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    local function main()
        
        local it_n,P,act,first_tr,E,itemz
        it_n = api.csi(0)
        
        if it_n<=1 then return end
        
        reaper.Undo_BeginBlock()

        itemz={}
        P={}

        for abi=1, it_n do
            local item = api.gsi(0,abi-1)
            local tr = api.git(item)
            itemz[abi] = item
            P[abi] = api.giv(item,"D_POSITION")
            if  last_tr and last_tr ~= tr then
                act="move to a single track"
            end
            last_tr = tr
        end
        
        api.pur(1)
        
        if  act=="move to a single track" then
            itemz, P = r.Reorder(itemz, P)
            first_tr = api.git(itemz[1])
            E = P[1] + api.giv(itemz[1],"D_LENGTH")
            for abi=2,#itemz do
                reaper.MoveMediaItemToTrack(itemz[abi],first_tr)
                api.siv(itemz[abi],'D_POSITION',E)
                E = E + api.giv(itemz[abi],"D_LENGTH")
            end
        else--move to separate tracks
            act="separate tracks"
            first_tr = api.git(itemz[1])
            local idx = api.gtv(first_tr,'IP_TRACKNUMBER')
            for abi=2,#itemz do
                reaper.InsertTrackAtIndex(idx,false)
                reaper.MoveMediaItemToTrack(itemz[abi],api.gt(0,idx))
                api.siv(itemz[abi],'D_POSITION',P[1])
                api.sts(api.git(itemz[abi]),true)
                idx = idx + 1
            end
            api.cmd(api.name('_SWS_NAMETKLIKEITEM'),0)--track name follow item name
        end
        
        api.pur(-1)

        reaper.Undo_EndBlock("Move selected items to "..act,-1)
    
    end
    
    main()
