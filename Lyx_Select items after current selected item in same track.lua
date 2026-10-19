    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    local function main()

        local item,track,all_lane,lane,idx
        
        api.mcw()
        mouse_item = api.mci()
        mouse_track = api.mct()

        if  not mouse_item then return end

        all_lane = api.gtv(mouse_track,'C_LANESCOLLAPSED') == 0
        lane     = api.giv(mouse_item,'I_FIXEDLANE')
        idx      = api.giv(mouse_item,'IP_ITEMNUMBER')

        next_item = api.gti(mouse_track,idx+1)
        
        if not next_item then return end

        api.pur(1) -- after every early return, so the UI never stays frozen
        
        selected = api.giv(mouse_item,'B_UISEL') + api.giv(next_item,'B_UISEL') == 2
        
        --api.cmd(40289,0)
        
        for abi = idx,api.cti(mouse_track)-1 do
            local item = api.gti(mouse_track,abi)
            if  api.giv(item,'I_FIXEDLANE') == lane then
                api.sis(item,not selected)
            end
        end
  
        item_group = reaper.GetToggleCommandState(1156) == 1
        
        if  item_group then
            api.cmd(40034,0)--select items in group
        end
        
        api.pur(-1)
        api.ua()

    end

    main()
