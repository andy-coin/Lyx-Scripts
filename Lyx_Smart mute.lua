    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    -----CUSTOM-----
        razor_toggle = true -- otherwise just mute

    --------------
    local function GetItemsInRange(track, areaStart, areaEnd)
        local items = {}
        local itemCount = reaper.CountTrackMediaItems(track)
        for k = 0, itemCount - 1 do 
            local item = reaper.GetTrackMediaItem(track, k)
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local itemEndPos = pos+length
    
            --check if item is in area bounds
            if (itemEndPos > areaStart and itemEndPos <= areaEnd) or
                (pos >= areaStart and pos < areaEnd) or
                (pos <= areaStart and itemEndPos >= areaEnd) then
                    table.insert(items,item)
            end
        end
    
        return items
    end
    
    --------------
    local function MuteRazorItems(razorMap)

        local newItems = {}
        
        --[[easy razor
        for abi = 1, #razorData.item do
            local item = razorData.item[abi] 
            --split items 
            local newItem = reaper.SplitMediaItem(item,razorData.min)
            if  not newItem then
                reaper.SplitMediaItem(item,razorData.max)
                table.insert(newItems,item)
            else
                reaper.SplitMediaItem(newItem, razorData.max)
                table.insert(newItems,newItem)
            end
        end--]]


            Save_time    = api.name("_SWS_SAVELOOP1")
            api.cmd(Save_time,0)
            
            api.cmd(40635,0)--Time selection: Remove (unselect) time selection
            api.cmd(40061,0)--Item: Split items at time selection or razor edit
            
            Restore_time = api.name("_SWS_RESTLOOP1")
            api.cmd(Restore_time,0)

        --[[multi razors
        for abi = 1, #razorMap do
            
            local Data,items
            
            Data = razorMap[abi]

            items = Data.items

            for abii = 1,#items do
                local item = items[abii]
                local newItem = reaper.SplitMediaItem(item,Data.areaStart)
                if  not newItem then
                    reaper.SplitMediaItem(item,Data.areaEnd)
                    table.insert(newItems,item)
                else
                    reaper.SplitMediaItem(newItem, Data.areaEnd)
                    table.insert(newItems,newItem)
                end
            end
        end--]]
        
        
        if  razor_toggle then
            local mute = api.giv(api.gsi(0,0),'B_MUTE')==1
            if  mute then
                api.cmd(40720,0)--Item properties: Unmute
                api.cmd(42957,0)--Select media items within razor edit area
                if true then return end
                api.cmd(40548,0)--heal items
            else
                api.cmd(40719,0)--Item properties: mute
            end
        else
            for abi=1,api.csi(0) do
                local item = api.gsi(0,abi-1)
                api.siv(item,'B_MUTE',1)
            end
        end
        
        --api.ua()
    end
    
    --------------
    local function main()
        
        local razor,razorMap = r.GetRazorEdits2(false,true)
        
        api.mcw()
        mouse_item = api.mci()

        if  razor then
            --api.pur(1)
            MuteRazorItems()
            return
            --api.pur(-1)
        elseif  api.mci() then
            for abi=1,api.csi(0) do
                if  api.gsi(0,abi-1) == mouse_item and api.gtv(api.git(mouse_item),'B_MUTE') == 0 then
                    api.cmd(r.ScriptID("Lyx Scripts/Lyx_Toggle items mute.lua"),0)--toggle items mute
                    return
                end
            end
        end
    
        r.SelTrackFilter()
        local editor,focus,currentWindow,trz,note
        
        editor = reaper.MIDIEditor_GetActive()
        focus = r.IsMidiEditorFocus(editor)
      
        if  editor and focus then
            trz = {}


            local tk,tk_idx,time,timeout,ITs
            
            tk_idx = 0
            time = api.now()
            timeout = 3
            ITs={}
            
            while (api.now() - time < timeout) do 
                
                tk = reaper.MIDIEditor_EnumTakes(editor, tk_idx, true)
                if not tk then break end
                
                ITs[#ITs+1] = reaper.GetMediaItemTake_Item(tk)
                
                note = reaper.MIDI_EnumSelNotes(tk, -1)
                cc = reaper.MIDI_EnumSelCC(tk, -1)
                if note == -1 and cc == -1 then goto NEXT end
        
                if  note ~= -1 then 
                    local retval, selected, muted = reaper.MIDI_GetNote(tk,note)
                    reaper.MIDIEditor_OnCommand(editor,(muted and 40058) or 40057,0)
                    return
                end
                
                if  cc ~= -1 then 
                    local retval, selected, muted = reaper.MIDI_GetCC(tk,cc)
                    reaper.MIDIEditor_OnCommand(editor,(muted and 40058) or 40057,0)
                    return
                end

                ::NEXT::
                tk_idx = tk_idx +1
            end     
            
            local mute = api.giv(ITs[1],'B_MUTE')

            for abi=1,#ITs do
                api.siv(ITs[abi],'B_MUTE',math.abs(mute-1))
            end
            api.ua()
            
            return
            --r.billboard('Toggle item\'s track mute')
        else
        
            for abi=1,api.cst(0) do
                local tr = api.gst(0,abi-1)
                local mute = api.gtv(tr,'B_MUTE')
                api.stv(tr,'B_MUTE',math.abs(mute-1))
            end
            --api.cmd(api.name('_BR_SAVE_SOLO_MUTE_ALL_TRACKS_SLOT_16'),0)-- save soloed tracks' solo state slot 16     
        end
    end
    
    reaper.Undo_BeginBlock()
    main()
    reaper.Undo_EndBlock("Mute track",-1)
