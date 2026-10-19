    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")

    local function main()

        api.ubb()
        api.pur(1)
        local itemzzz,last_tr,trzzz,trzz,trz,comping
        
        
        --[[itemzzz={}
        for abi=1,api.csi(0) do
            itemzzz[#itemzzz+1] = api.gsi(0,abi-1)
        end--]]
        
        itemzzz=r.SaveItems()
        trzzz=r.SaveTracks()
        trzz={}
        
        for abi=1,#itemzzz  do
            local tr = reaper.GetMediaItemTrack(itemzzz[abi])    
            if  not last_tr or last_tr~=tr then
                trzz[#trzz+1]=tr
            end
            last_tr=tr
        end
        
        local win = reaper.BR_GetMouseCursorContext()
        local under_mouse_tr = reaper.BR_GetMouseCursorContext_Track()

        trz=(#trzz>#trzzz and trzz) or trzzz 
        
        for abi=1,#trz do
            local tr = trz[abi]
            if  tr == under_mouse_tr then
                local lane_n=reaper.GetMediaTrackInfo_Value(tr,"I_NUMFIXEDLANES")
                if  lane_n>1 and win ~= 'tcp' then
                    local fold=reaper.GetMediaTrackInfo_Value(tr,"C_LANESCOLLAPSED")
                    fold=(fold==0 and 1) or 0
                    api.cmd(43101-fold,0)--big/small lanes
                    api.cmd(40091+fold,0)--show/hide lanes button
                    reaper.SetMediaTrackInfo_Value(tr,"C_LANESCOLLAPSED",fold)
                    for suni=1,lane_n do
                        local _,tr_name,lane_name,new_name
                        if  api.gtv(tr,"C_LANEPLAYS:"..(suni-1))==1 then 
                            --change name
                            _,tr_name=api.ts(tr,"P_NAME","",false)
                            _,lane_name=api.ts(tr,"P_LANENAME:"..(suni-1),"",false)
                            new_name=tr_name:gsub("(   %[ .* %])","").."   [ "..lane_name..' ]'
                            api.ts(tr,"P_NAME",new_name,true)
                            break
                        end
                    end   
                    api.cmd(40913,0)
                    goto END
                elseif lane_n == 1 and api.gtv(tr,'I_FREEMODE')==2 then
                    api.stv(tr,'I_FREEMODE',0)
                    goto END
                end
            end
        end

        do
            local fold,lane_n
            for abi=1,#trz do
                lane_n=reaper.GetMediaTrackInfo_Value(trz[abi],"I_NUMFIXEDLANES")
                if  lane_n>1 and win ~= 'tcp' then
                    comping = true
                    fold=reaper.GetMediaTrackInfo_Value(trz[abi],"C_LANESCOLLAPSED")
                    fold=(fold==0 and 1) or 0
                    api.cmd(43101-fold,0)--big/small lanes
                    api.cmd(40091+fold,0)--show/hide lanes button
                    reaper.SetMediaTrackInfo_Value(trz[abi],"C_LANESCOLLAPSED",fold)
                    for suni=1,lane_n do
                        if  api.gtv(trz[abi],"C_LANEPLAYS:"..(suni-1))==1 then 
                            --change name
                            _,tr_name=api.ts(trz[abi],"P_NAME","",false)
                            _,lane_name=api.ts(trz[abi],"P_LANENAME:"..(suni-1),"",false)
                            new_name=tr_name:gsub("(   %[ .* %])","").."   [ "..lane_name..' ]'
                            api.ts(trz[abi],"P_NAME",new_name,true)
                            break
                        end
                    end  
                elseif lane_n == 1 and api.gtv(trz[abi],'I_FREEMODE')==2 then
                    comping = true
                    api.stv(trz[abi],'I_FREEMODE',0)
                end
            end
        end

        if  not comping then 
            local done = {} -- each parent toggles only once
            for abi=1,#trz do
                local parent,key,B_AUTO,children
                parent = (reaper.GetMediaTrackInfo_Value(trz[abi],"I_FOLDERDEPTH")==1 and trz[abi]) or r.HaveParent(trz[abi],false)
                if  parent and not done[parent] then
                    done[parent] = true
                    reaper.SetOnlyTrackSelected(parent)
                    key=reaper.GetMediaTrackInfo_Value(parent,"I_FOLDERCOMPACT")

                    reaper.SetMediaTrackInfo_Value(parent,"I_FOLDERCOMPACT",(key+1)%3)

                    cmd=reaper.NamedCommandLookup("_SWS_SELCHILDREN")
                    reaper.Main_OnCommand(cmd,0)--select only children track

                    if key==1 then
                        for abii=1,reaper.CountSelectedTracks(0) do
                            reaper.SetMediaTrackInfo_Value(reaper.GetSelectedTrack(0,abii-1),"I_RECARM",0)
                            reaper.SetMediaTrackInfo_Value(reaper.GetSelectedTrack(0,abii-1),"I_RECARM_AUTO",0)
                        end
                    elseif key==2 then
                        B_AUTO=reaper.GetMediaTrackInfo_Value(parent,"B_AUTO_RECARM")
                        children={}
                        for abii=1,reaper.CountSelectedTracks(0) do
                            children[abii]=reaper.GetSelectedTrack(0,abii-1)
                            reaper.SetMediaTrackInfo_Value(children[abii],"I_RECARM",0)
                            reaper.SetMediaTrackInfo_Value(children[abii],"I_RECARM_AUTO",B_AUTO)
                        end
                        r.SameTCPH(children,parent)
                    end
                end
            end
        end

        ::END::

        r.RestoreTracks(trzzz)
        r.RestoreItems(itemzzz)
        reaper.UpdateArrange()
        api.pur(-1)
        api.ueb(0,"Toggle track folder state",-1)
    end

    reaper.defer(main)

