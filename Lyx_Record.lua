    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    -----CUSTOM-----
    
        ---buffer size-
        auto_change_buffersize = true
        small = 128
        large = 2048
        --
        auto_group = true
        auto_color = false

    --------------
    local function SetMediaItemColor()
        
        local GUID={}
    
        for abi=1,reaper.CountTracks(0) do
            
            local tr=reaper.GetTrack(0,abi-1)
            for abig=1,reaper.CountTrackMediaItems(tr) do
                local item=reaper.GetTrackMediaItem(tr,abig-1)
                local color=reaper.GetMediaItemInfo_Value(item,"I_CUSTOMCOLOR")
                local tr_color=reaper.GetMediaTrackInfo_Value(tr,"I_CUSTOMCOLOR")
                
                if  color==0  then 
                    local guid,take,Audio_Midi,_
                    _,guid=reaper.GetSetMediaItemInfo_String(item,"GUID","",false)
                    take=reaper.GetActiveTake(item)
                    Audio_Midi=(take and reaper.TakeIsMIDI(take) and midi ) or audio
                    color=((tr_color~=0 and tr_color~=12599296 ) and tr_color) or Audio_Midi
                    reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",color)
                    GUID[#GUID+1]=guid
                end
                
            end
        
            
        end
        
        reaper.UpdateArrange()

        GUID=serialize(GUID)
        
        return GUID
        
    end
    
    --------------
    local function SaveMIDIRecItem(rec_tr)
        
        local track_table={}

        for abi=1,#rec_tr do
            local mode, _, tr, tr_guid, guid
            tr = rec_tr[abi]
            mode = api.gtv(tr,"I_RECMODE")
            if  mode==7 or mode==8 then
                tr_guid = api.tid(tr)
                local item_table = {}
                for abii = 1,api.cti(tr) do
                    local item, item_guid, take = api.gti(tr,abii-1)
                    item_guid = api.iid(item)
                    take = api.gatk(item)
                    if  api.itkm(take) then
                        local _,notecnt, ccevtcnt, textsyxevtcnt = reaper.MIDI_CountEvts(take)
                        item_table[#item_table+1] = {item_guid = item_guid, notecnt = notecnt, ccevtcnt = ccevtcnt, textsyxevtcnt = textsyxevtcnt}
                    end
                end
                track_table[#track_table+1] = {tr_guid,item_table}
            end
        end 

        if #track_table == 0 then return "" end

        return serialize(track_table)
    end
    
    --------------
    local function SelectRecMIDIitem(trs,P,rec_point)

        trs = unserialize(trs)

        for abi = 1,#trs do
            local tr = api.idt(0,trs[abi][1])
            if  api.check(0,tr,"MediaTrack*") then
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
    local function RestoreItemColor(items)
        
        items = unserialize(items)

        for abi=1,#items do
            local item=reaper.BR_GetMediaItemByGUID(0,items[abi])
            if  reaper.ValidatePtr2(0,item,"MediaItem*") then
                reaper.SetMediaItemInfo_Value(item,"I_CUSTOMCOLOR",0)
            end
        end
        
        reaper.UpdateArrange()

    end  
    
    --------------
    local function SwitchItemTint(toggle)

        local setting=reaper.SNM_GetIntConfigVar("tinttcp",-1)
        setting=(toggle==1 and 1195) or 1191
        reaper.SNM_SetIntConfigVar("tinttcp",setting)
        reaper.UpdateArrange()
        
    end

    -- put back the theme's item background saved at record start (Play-Stop does the same)
    local function RestoreItemTheme()

        local bg = tonumber(api.load("Record","col_mi_bg"))
        if  not bg then return end
        reaper.SetThemeColor("col_mi_bg" ,bg,0)
        reaper.SetThemeColor("col_mi_bg2",tonumber(api.load("Record","col_mi_bg2")) or -1,0)
        api.save("Record","col_mi_bg","",false)
        SwitchItemTint(1)

    end

    -- colours are set once at record start; this loop only waits for recording to end
    local function WaitRecordEnd()

        if  api.gps()&4 == 4 then return reaper.defer(WaitRecordEnd) end
        RestoreItemTheme()

    end

    local function ChangeBufferSize()
        
        local pro_n = r.CountProjects()
        if  pro_n > 1 then
            for abi=1,pro_n do 
                if  reaper.GetPlayState(abi-1)~=0 then 
                    running=true
                    break
                end
            end
        end

        if  not running then
            r.SetBufferSize(small)
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
        local Item=reaper.GetToggleCommandState(40253)==1
        local Time=reaper.GetToggleCommandState(40076)==1
        
        if  play ~= 5 then --not record
            
            local rec_tr,_

            rec_tr = r.GetRecTrack(false,true)
            
            if  #rec_tr>0 then
                
                local itemz,midi_tr_itemz,P

                itemz = SetMediaItemColor()
                midi_tr_itemz = SaveMIDIRecItem(rec_tr)

                api.save("Record - 0 color item",pro_name,itemz,false)
                api.save("Record - midi track item",pro_name,midi_tr_itemz,false)

                if  #rec_tr>1 then 
                    r.billboard("Recording multi tracks~~",1.5)
                end
                
                if  auto_change_buffersize then ChangeBufferSize() end

                if  reaper.GetToggleCommandState(40740)==1 then
                    --reaper.Main_OnCommand(40740,0)--disable all track auto arm 
                end
                
                for abi = 1, #rec_tr do
                    local tr = rec_tr[abi]
                    if api.gtv(tr,'I_RECMODE') == 7 and Time then
                        api.stv(tr,'I_RECMODE',8)
                    elseif api.gtv(tr,'I_RECMODE') == 8 and not Time then
                        api.stv(tr,'I_RECMODE',7)
                    end
                end

                if  Time then -- or Item then
                    reaper.Main_OnCommand(43153,0)-- New recording don't adds lanes
                elseif  reaper.GetToggleCommandState(42702)==0 then
                    reaper.Main_OnCommand(42702,0)-- New recording adds lanes
                end                

                if  api.load("Record","col_mi_bg") == "" then -- remember the theme colours once
                    api.save("Record","col_mi_bg" ,reaper.GetThemeColor("col_mi_bg",0),false)
                    api.save("Record","col_mi_bg2",reaper.GetThemeColor("col_mi_bg2",0),false)
                end
                reaper.SetThemeColor("col_mi_bg",rec,0)
                reaper.SetThemeColor("col_mi_bg2",rec,0)
                SwitchItemTint(0)
                
                rec_point=( play==1 and reaper.GetPlayPositionEx(0)) or reaper.GetCursorPositionEx(0)
                
                api.save("Record - Again point",pro_name,rec_point,false)
                
                api.cmd(41186,0) -- New recording trims existing items (tape mode)
                r.ShowHideTrackLaneNames('Hide')
                reaper.Main_OnCommand(1013,0) --record
                WaitRecordEnd()
                api.cmd(40527,0)--Clear all peak indicators
                
            else

                r.billboard("There is no record-arm track~",1.5)
            
            end            
 
        else --stop record

            local midi_tr,color_itemz

            local P = api.gpc()
            reaper.Main_OnCommand(1013,0)  
            
            color_itemz = api.load("Record - 0 color item",pro_name)
            midi_tr = api.load("Record - midi track item",pro_name)
            RestoreItemColor(color_itemz) 
            RestoreItemTheme()
             
            if auto_color then api.cmd(r.ScriptID("Lyx Scripts/Lyx_Set random color .lua"),0) end --change color
            if auto_group and api.csi(0)>1 then api.cmd(40032,0) end --group items
            
            local rec_point = api.load("Record - Again point",pro_name)

            SelectRecMIDIitem(midi_tr,P,rec_point)
            SetItemSnapOffset()
            r.ShowHideTrackLaneNames('Show')
        end
        
    end
    
    -------------------------------------RUN---------------------------------------
    
    rec   = reaper.ColorToNative(150,0,0)|0x1000000
    audio = reaper.ColorToNative(29,73,127)|0x1000000
    midi  = reaper.ColorToNative(28,108,52)|0x1000000

    reaper.Undo_BeginBlock() 
    api.cc()
    main()
    reaper.Undo_EndBlock("Recording",-1)

    current_time = os.date("*t")
