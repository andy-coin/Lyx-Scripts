

    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_lib._Lyx_HOME")

    --[[
    --------------
    local function SplitRazorEdits(razorEdits)
        local allItems={}
        local newItems = {}
        local tracks = {}
        reaper.PreventUIRefresh(1)
        for i = 1, #razorEdits do
            local areaData = razorEdits[i]
            if not areaData.isEnvelope then
                local items = areaData.items
                
                --recalculate item data for tracks with previous splits
                if tracks[areaData.track] ~= nil then 
                    items = GetItemsInRange(areaData.track, areaData.areaStart, areaData.areaEnd)
                end
                
                for j = 1, #items do 
                    local item = items[j]
                    --split items 
                    local newItem = reaper.SplitMediaItem(item, areaData.areaStart)
                    if newItem == nil then
                        r_item=reaper.SplitMediaItem(item, areaData.areaEnd)
                        table.insert(newItems,item)
                        table.insert(allItems,item)
                        table.insert(allItems,r_item)
                    else
                        r_item=reaper.SplitMediaItem(newItem, areaData.areaEnd)
                        table.insert(newItems,newItem)
                        table.insert(allItems,item)
                        table.insert(allItems,newItem)
                        table.insert(allItems,r_item)
                    end
                end
    
                tracks[areaData.track] = 1
            end
        end
        reaper.PreventUIRefresh(-1)
        
        return newItems,allItems
    end
    
    --------------
    local function IsCompTrack(it,e)
        
        if it then
            tr=reaper.GetMediaItemTrack(it)
        elseif e then
            tr=reaper.Envelope_GetParentTrack(e)
        end
        if not tr then return false end
        
        local parent=reaper.GetParentTrack(tr)
        if not parent then return false end
        local _,layout=reaper.GetSetMediaTrackInfo_String(parent,"P_TCP_LAYOUT","",false)
        if layout=="d3 ------ Red Fader" then
            return parent
        else
            return false
        end
        
    end
    
    --------------
    local function MoveItem(mom,it)
        reaper.SetOnlyTrackSelected(mom)
        reaper.Main_OnCommand(40289,0)
        reaper.SetMediaItemSelected(it,true)
        point=reaper.GetMediaItemInfo_Value(it,"D_POSITION")
        reaper.Main_OnCommand(40698,0)--copy items
        reaper.SetEditCurPos(point,false,false)
        reaper.Main_OnCommand(42398,0)--paste items
        return reaper.GetSelectedMediaItem(0,0)
    end
    
    --------------
    local function MoveEnv(mom,E,int)
        
        reaper.SetOnlyTrackSelected(mom)
        env=reaper.GetTrackEnvelopeByName(mom,E[int].envelopeName)
        if not env then 
            if     E[int].envelopeName == "Volume" then reaper.Main_OnCommand(40406, 0) -- show track volume envelope
            elseif E[int].envelopeName == "Pan" then reaper.Main_OnCommand(40407, 0)    -- show track pan envelope
            elseif E[int].envelopeName == "Mute" then reaper.Main_OnCommand(40867, 0)   -- show track mute envelope
            elseif E[int].envelopeName == "Volume (Pre-FX)" then reaper.Main_OnCommand(40408, 0) -- show track pre-FX volume envelope
            end
            env=reaper.GetTrackEnvelopeByName(mom,E[int].envelopeName)
        end
        
        reaper.DeleteEnvelopePointRange(env,E[int].areaStart,E[int].areaEnd)
        for abii=1,#E[int].envelopePoints do
            Env=E[int].envelopePoints[abii]
            reaper.InsertEnvelopePoint(env,Env.time,Env.value,Env.shape,Env.tension,true)
        end
    
    end
    
    --------------
    local function main_v1()
    
        reaper.Undo_BeginBlock()
        reaper.PreventUIRefresh(-1)
        local P=reaper.GetCursorPosition()
        
        trackz=r.SaveTracks()
        
        local razorMaps=r.GetRazorEdits()
        if #razorMaps>0 then 
            new_itemz={}
            itemz,ori_itemz=SplitRazorEdits(razorMaps)
            if #itemz>0 then
                for abi=1,#itemz do
                    mom=IsCompTrack(itemz[abi])
                    if not mom then goto END end
                    new_itemz[#new_itemz+1]=MoveItem(mom,itemz[abi])
                    ::END::
                end
                reaper.Main_OnCommand(40289,0)
                for abi=1,#ori_itemz do
                    reaper.SetMediaItemSelected(ori_itemz[abi],true)
                end
                reaper.Main_OnCommand(40548,0)--Heal items
                reaper.Main_OnCommand(40289,0)
                for abi=1,#new_itemz do
                    reaper.SetMediaItemSelected(new_itemz[abi],true)
                end
            end
            for abi=1,#razorMaps do
                if not razorMaps[abi].isEnvelope then goto NEXT end
                mom=IsCompTrack(_,razorMaps[abi].envelope)
                if not mom then goto NEXT end
                MoveEnv(mom,razorMaps,abi)
                ::NEXT::
            end
        else
            it_n=reaper.CountSelectedMediaItems(0)
            if it_n>0 then
                itemz={}
                for abi=1,it_n do
                    itemz[abi]=reaper.GetSelectedMediaItem(0,abi-1)
                end
                for abi=1,#itemz do
                    mom=IsCompTrack(itemz[abi])
                    if not mom then goto END end
                    MoveItem(mom,itemz[abi])
                    ::END::
                end
            end
        end
        
        reaper.Main_OnCommand(40297,0)
        for abi=1,#trackz do
            reaper.SetTrackSelected(trackz[abi],true)
        end
        reaper.SetEditCurPos(P,false,false)
        reaper.PreventUIRefresh(1)
        reaper.Undo_EndBlock("Track versions-Comp items",-1)
    end--]]
    
    local function main_v2()

    end 
       
    main_v2()
