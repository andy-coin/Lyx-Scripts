    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    -----CUSTOMIZE-----
    
        range = 2 --second
        pre_offset = (api.gps()~=0 and 0.5) or 0 --second
        target_color = reaper.ColorToNative(255,236,0)|0x1000000 --yellow

    local function main()

        itemzzz = r.SaveItems()

        razor,razorMap = r.GetRazorEdits(true)

        cursor = (api.gps()%2~=0 and api.gpc()) or api.gec()
        
        itemz = ( razor and razorMap.item) or itemzzz
        edge_s = (razor and razorMap.min) or cursor-range-pre_offset
        edge_e = (razor and razorMap.max) or cursor-pre_offset
        
        api.pur(1)
        new_itemz={}
        api.cmd(40289,0)

        for abi=1,#itemz do
            
            local item = itemz[abi]
            local take = reaper.GetActiveTake(item)
            if  not take or reaper.TakeIsMIDI(take) then goto NEXT end -- skip empty and MIDI items

            local target_item = reaper.SplitMediaItem(item,edge_s)

            if  target_item then
                new_itemz[#new_itemz+1] = reaper.SplitMediaItem(target_item,edge_e)
                api.siv(target_item,"I_CUSTOMCOLOR",target_color)
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
                        end
                        api.siv(left_item,"D_LENGTH",cursor-Start)
                    end
                end
            end
            
            ::NEXT::
            
        end

        api.pur(-1)
        api.ua()

        r.RestoreItems((#new_itemz>0 and new_itemz) or itemzzz )

    end

    api.ubb()
    main()
    api.ueb(0,"Split item(s) and mark color as bad section",-1)
