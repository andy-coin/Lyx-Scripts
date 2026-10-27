    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_lib._Lyx_HOME")
    local L=require("_lib._Lyx_LaneName")
    
    ---CUSTOM---
        --return to last or stay in first 
        FallBack = false
        
    local function Up()
        
        local _,trzzz,trzz,trz

        trzzz = r.SaveTracks()

        trzz = {}
        for abi=1,api.csi(0) do
            local item,tr
            item = api.gsi(0,abi-1)
            tr = api.git(item)
            trzz[#trzz+1] = tr
        end
        
        _,trzz = r.KillTable(trzz)
        
        trz = ((#trzz >= #trzzz and #trzz>1) and trzz) or trzzz
        if #trz == 0 then return end

        for abi=1,#trz do
            local tr,lane_n,playing_lane
            tr=trz[abi]
            lane_n=api.gtv(tr,"I_NUMFIXEDLANES")
            if lane_n==1 then goto Next end
            
            for abig=1,lane_n do
                if  api.gtv(tr,"C_LANEPLAYS:"..(abig-1)) == 1 then
                    
                    local _,tr_name,lane_name,new_name,current_lane,new_lane
                    
                    current_lane = abig - 1
                    playing_lane = true        
                    
                    if  FallBack then
                        new_lane = (current_lane == 0 and lane_n-1 ) or current_lane -1
                    else
                        new_lane = (current_lane == 0 and 0 ) or current_lane -1
                    end

                    api.stv(tr,"C_LANEPLAYS:"..(new_lane),1)

                    --change name
                    L.show(tr,new_lane)

                    --select items in same position
                    if  FallBack  or ( not FallBack and current_lane ~= 0 ) then

                        local old_items,new_items,P,p,E,e
                        old_items = {}
                        new_items = {}

                        for abige = 1, api.cti(tr,0) do
                            local item,item_lane
                            item = api.gti(tr,abige-1)
                            item_lane = api.giv(item,"I_FIXEDLANE")
                            if  item_lane == current_lane and api.iis(item) then
                                old_items[#old_items+1] = item
                            elseif item_lane == new_lane then
                                new_items[#new_items+1] = item
                            end
                        end

                        for abige = #old_items,1,-1 do
                            P = api.giv(old_items[abige],'D_POSITION')
                            E = P + api.giv(old_items[abige],'D_LENGTH')

                            for  abigel = #new_items, 1, -1 do
                                p = api.giv(new_items[abigel],'D_POSITION')
                                e = p + api.giv(new_items[abigel],'D_LENGTH')
                                if  (p >= P and p < E ) or ( e > P and e <= E ) or ( p < P and e > E ) then
                                    api.sis(new_items[abigel],true)
                                    table.remove(new_items,abigel)
                                end
                            end
                            api.sis(old_items[abige],false)
                        end
                    end

                    break
                end
            end    

            if  not playing_lane then
                new_lane = lane_n-1
                local _,tr_name,lane_name,new_name
                api.stv(tr,"C_LANEPLAYS:"..new_lane,1)

                --change name
                L.show(tr,new_lane)
            end
            ::Next::   
        end
        api.ua()
    end

    api.ubb()
    Up()
    api.ueb(0,"Switch to next track version",-1)
    
    
    
    
