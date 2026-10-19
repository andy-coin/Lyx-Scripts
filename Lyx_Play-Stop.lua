 
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    -----CUSTOM-----
    
        ---buffer size-
        auto_change_buffersize = true
        small = 128
        large = 2048
        auto_group = true
        auto_color = false
    
    local function UpdateRecTracksLaneName()

        r.SaveTracks(true)
        r.RestoreTracks('rec_tracks')

        for abi=1,api.cst(0) do
            local tr,lane_n
            tr = api.gst(0,abi-1)
            lane_n = api.gtv(tr,"I_NUMFIXEDLANES")
        
            if  lane_n <= 1 then goto NEXT end
            
            for abi=1,lane_n do
            
                if  api.gtv(tr,"C_LANEPLAYS:"..(abi-1))==1 then 
                    --change name
                    _,tr_name=api.ts(tr,"P_NAME","",false)
                    _,lane_name=api.ts(tr,"P_LANENAME:"..(abi-1),"",false)
                    new_name=tr_name:gsub("(   %[ .* %])","").."   [ "..lane_name..' ]'
                    api.ts(tr,"P_NAME",new_name,true)
                    break
                end
            
            end
            ::NEXT::
        end
        r.RestoreTracks(true)
    end
    
    --reaper.SetThemeColor("col_tl_bgsel2",16757568,0)
    
    local skip_color = api.load('timeline','skip_color')
  
    local function Skip_TimeSel()
            
        local current_color = reaper.GetThemeColor("col_tl_bgsel2")
        
        if  api.gps() == 1 and tonumber(current_color) == tonumber(skip_color) then
            
            cursor = api.gpc()
            Start,End = reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
            
            if  math.abs(cursor-Start) < 2e-2 then
                local p = api.gec()
                api.sec(End,false,true)
                api.sec(p,false,false)
                return
            end
            reaper.defer(Skip_TimeSel)
        end
        
    end
        
        
    --------------
    local function SelectRecMIDIitem(trs,P,rec_point)
    
        trs = unserialize(trs)
    
        for abi = 1,#trs do
            local tr = api.idt(0,trs[abi][1])
            if  api.check(0,tr,"MeidaTrack*") then
                for abii = 1, api.cti(tr) do
                    local item = api.gti(tr,abii-1) 
                    if  item then
                        local p = api.giv(item,"D_POSITION") 
                        local l = api.giv(item,"D_LENGTH")
                        if  math.abs(P - (p+l)) < 0.1 then
                            local offset, take
                            api.sis(item,true)
                            api.siv(item, "C_BEATATTACHMODE", 1)
                            api.siv(item,  "C_AUTOSTRETCH", 1)
                        end
                    end
                end
            end
        end
    end
    
    
    --------------
    local function RestorItemColor(items)
        
        items=unserialize(items)

        for abi=1,#items do
            local item=reaper.BR_GetMediaItemByGUID(0,items[abi])
            if  reaper.ValidatePtr2(0,item,"MediaItem*") then
                reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",0)
            end
        end

        reaper.SetThemeColor("col_mi_bg" ,audio,0)
        reaper.SetThemeColor("col_mi_bg2",audio,0)
        
        reaper.UpdateArrange()

    end  
    
    --------------
    local function SwitchItemTint(toggle)

        local setting=reaper.SNM_GetIntConfigVar("tinttcp",-1)
        setting=(toggle==1 and 1195) or 1191
        reaper.SNM_SetIntConfigVar("tinttcp",setting)
        reaper.UpdateArrange()
        
    end

    --------------
    local function ChangeBufferSize(buffer_size)
        
        pro_n= r.CountProjects()
        
        if  pro_n > 1 then
            for abi=1,pro_n do 
                if  reaper.GetPlayState(abi-1)~=0 then 
                    running=true
                    break
                end
            end
        end

        if  not running then
            r.SetBufferSize(buffer_size)
        end        

    end
    
    local function SetItemSnapOffset()
    
        for abi = 1, api.csi(0) do
            local item, pos, length, _, measure, item_qn, qn, qn_time, next_qn, next_qn_time, offset
            item = api.gsi(0, abi-1)
            pos = api.giv(item, 'D_POSITION')
            length = api.giv(item, 'D_LENGTH')
        
            _, measure = reaper.TimeMap2_timeToBeats(0, pos)
            item_qn = reaper.TimeMap2_timeToQN(0, pos)
    
            _, qn = reaper.TimeMap_GetMeasureInfo(0, measure) 
            _, next_qn = reaper.TimeMap_GetMeasureInfo(0, measure+1) 
    
            qn_time = reaper.TimeMap_QNToTime_abs(0, qn)
            next_qn_time = reaper.TimeMap_QNToTime_abs(0, next_qn)
    
            if pos == qn_time then
                -- do nothing
                offset = 0 
            elseif  next_qn_time <= pos + length then
                offset = next_qn_time - pos
            else
                qn_time = reaper.TimeMap_QNToTime_abs(0,math.floor(item_qn)+1)
                if  qn_time <= pos + length then
                    offset = qn_time - pos
                else
                    offset = 0
                end
            end
            api.siv(item, 'D_SNAPOFFSET', offset)
        end
    
    end
    
    --------------------------------------MAIN---------------------------------------
    local function main()
        
        local play=reaper.GetPlayState() 

        if  play  == 5 then --recording
            
            local midi_tr,color_itemz
            
            local P = api.gpc()
            reaper.Main_OnCommand(40044,0)--stop record
            SwitchItemTint(1)
            color_itemz = api.load("Record - 0 color item",pro_name)
            midi_tr = api.load("Record - midi track item",pro_name)
            RestorItemColor(color_itemz)
            
            if auto_group and api.csi(0)>1 then api.cmd(40032,0) end --group items
            if auto_color then api.cmd(r.ScriptID("Lyx Scripts/Lyx_Set random color .lua"),0) end --change color
            
            local rec_point = api.load("Record - Again point",pro_name,rec_point)
            SelectRecMIDIitem(midi_tr,P,rec_point)
            SetItemSnapOffset()
            r.ShowHideTrackLaneNames('Show')
            --UpdateRecTracksLaneName()
            --api.cmd(api.name('_RS94529c0d6874ab92020a5639fa8e92c13c7bc76b'),0)--rename selected items to track name
            --SelectRecMIDIitem(midi_tr,P,rec_point)

        elseif play == 0 or play == 2 then

            BufferSize=(r.GetRecTrack(true) and small) or large
            
            if  auto_change_buffersize then ChangeBufferSize(BufferSize) end
            
            reaper.Main_OnCommand(40044,0) -- play/stop
            
            Skip_TimeSel()
            
        else                               --not record 
        
            pause_mode=api.load("Play mode","Play mode",false)
            
            if  pause_mode=="1" then
                reaper.SetEditCurPos(reaper.GetPlayPosition(),false,false)
            end
            
            reaper.Main_OnCommand(40044,0) -- play/stop
            
            BufferSize=(r.GetRecTrack(true) and small) or large
            
            if auto_change_buffersize then ChangeBufferSize(BufferSize) end
        
            
        end
      
    end
    
    -------------------------------------RUN---------------------------------------
    
    rec = 26607616
    audio= 18696831
    midi = 18639924

    reaper.Undo_BeginBlock() 
    if  api.load('practice mode','snapshot') == '1' then
        api.cmd(api.name('_SWSSNAPSHOT_GET_NEXT'),0)--next snapshot
    else
        --if  r.IsMidiEditorFocus() then
        --    main()
        --    api.cmd(api.name('_SN_FOCUS_MIDI_EDITOR'),0)
        --else
        main()
        --end
    end

    reaper.Undo_EndBlock("Play/Stop",-1)


