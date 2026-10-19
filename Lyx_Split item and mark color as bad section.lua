    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    
    -----CUSTOMIZE-----

        range = 1 --second
        pre_offset = (api.gps()~=0 and 0.5) or 0 --second
        target_color = 26317201 --gray (RGB)

    --------------
    local function ToggleItemGroups()
        
        local id={}
        
        for abi=1,api.csi(0) do
            local item=reaper.GetSelectedMediaItem(0,abi-1)
             if r.IsItemVisible(item) then
                id[#id+1]=reaper.GetMediaItemInfo_Value(item,"I_GROUPID")
             end
        end    
         
        _,id = r.KillTable(id)
    
        if  #id==1 and id[1]~=0 then
            reaper.Main_OnCommand(40033,0)--ungroup items
            reaper.Main_OnCommand(40032,0)--group items
        end
    end
    
    --------------
    local function main()

        itemzzz = r.SaveItems()

        razor,razorMap = r.GetRazorEdits(true)

        cursor = (api.gps()%2~=0 and api.gpc()) or api.gec()
        
        itemz = ( razor and razorMap.item) or itemzzz
        edge_s = (razor and razorMap.min) or cursor-range-pre_offset
        edge_e = (razor and razorMap.max) or cursor-pre_offset
        
        --api.pur(1)
        new_itemz={}
        target_itemz={}
        api.cmd(40289,0)

        for abi=1,#itemz do
            
            local item = itemz[abi]
            if  reaper.TakeIsMIDI(reaper.GetActiveTake(item))  then goto NEXT end

            local target_item = reaper.SplitMediaItem(item,edge_s)

            if  target_item then
                new_itemz[#new_itemz+1] = reaper.SplitMediaItem(target_item,edge_e)
                api.siv(target_item,"I_CUSTOMCOLOR",target_color)
                target_itemz[#target_itemz+1] = target_item
            else
                local tr,left_item,Start,End,new_item
                tr = api.git(item)
                --lane = api.giv(item,"I_FIXEDLANE")
                left_item = api.gti(tr,api.giv(item,"IP_ITEMNUMBER")-1)
                if  left_item then
                    Start = api.giv(left_item,"D_POSITION")
                    End = Start + api.giv(left_item,"D_LENGTH")

                    if  Start <= edge_s and End >= edge_s and api.giv(left_item,"I_CUSTOMCOLOR")==target_color then
                        new_item = reaper.SplitMediaItem(item,cursor)
                        if  new_item then
                            reaper.DeleteTrackMediaItem(tr,item)
                            new_itemz[#new_itemz+1] = new_item
                            target_itemz[#target_itemz+1] = left_item
                        end
                        api.siv(left_item,"D_LENGTH",cursor-Start)
                    end
                end
            end
            
            ::NEXT::
            
        end
        
        if  #target_itemz > 0 then
            api.cmd(40289,0)
            for abi=1,#target_itemz do
                api.sis(target_itemz[abi],1)
            end
            ToggleItemGroups()
            api.cmd(40289,0)
            for abi=1,#new_itemz do
                api.sis(new_itemz[abi],1)
            end
            ToggleItemGroups()
        end
        
        api.pur(-1)
        api.ua()

        r.RestoreItems((#new_itemz>0 and new_itemz) or itemzzz )

    end

    api.ubb()
    main()
    api.ueb(0,"Split item(s) and mark color as bad section",-1)
