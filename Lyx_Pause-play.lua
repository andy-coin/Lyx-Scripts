    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path .. ";" .. script_path .. "?.lua"
    local r=require("_Lyx_HOME")
    
    --------------
    local function Update_record_content(tbl)
        
        midi_itemz = unserialize(tbl)

        for abi=1,#midi_itemz do
            local _, tr, item_tbl
            
            tr = api.idt(0, midi_itemz[abi][1])
            if not tr then return true end

            item_tbl = midi_itemz[abi][2]

            if api.cti(tr) ~= #item_tbl then return true end

            for abii=1, #item_tbl do
                local data, item, take
                data = item_tbl[abii]

                item = api.idi(0, data.item_guid)
                if not item then return true end

                take = api.gatk(item)
                if  api.itkm(take) then
                    local _,notecnt, ccevtcnt, textsyxevtcnt = reaper.MIDI_CountEvts(take)
                    if notecnt ~= data.notecnt or ccevtcnt ~= data.ccevtcnt or textsyxevtcnt ~= data.textsyxevtcnt then
                        return true
                    end
                end
            end
        end 

        return false
        
    end
    
    --------------
    local function main()
        
        local P=reaper.GetCursorPosition()

        if  Play==5 then
            
            reaper.Undo_BeginBlock2(0)
            local midi_tr,A
            api.cmd(1016,0)--play/stop 
                            
            midi_tr = api.load("Record - midi track item",pro_name)
            A = api.load("Record - Again point",pro_name)
            
            if  tonumber(A)  then
                reaper.SetEditCurPos(A,false,false)
            end
            
            if not Update_record_content(midi_tr) and api.csi(0)==0 then
                reaper.Undo_EndBlock2(0,"Stop recording",-1) -- keep the undo block balanced
                return
            end
            
            reaper.Undo_EndBlock2(0,"",-1)
            reaper.Undo_DoUndo2(0)
            reaper.Undo_BeginBlock2(0)
            
            
            api.cmd(1013,0) --record
            
            api.cmd(40527,0)--Clear all peak indicators
            reaper.SetEditCurPos(P,false,false)
            
            reaper.Undo_EndBlock2(0,"Record again at same spot",-1)
        
        elseif Play==1 then
            
            api.cmd(40328,0)--stop and move edit cursor
        
        else
        
            pause_mode=reaper.GetExtState("Play mode","Play mode",false)

            if  pause_mode~="1" then  
                pause_mode=0
                -- entering pause mode: remember the theme's own cursor colours, then tint them cyan
                api.save("Play mode","col_cursor" ,reaper.GetThemeColor("col_cursor",0),false)
                api.save("Play mode","col_cursor2",reaper.GetThemeColor("col_cursor2",0),false)
                reaper.SetThemeColor("col_cursor" ,reaper.ColorToNative(32,225,212),0)
                reaper.SetThemeColor("col_cursor2",reaper.ColorToNative(34,195,218),0)
            else
                -- leaving pause mode: put the theme's cursor colours back (-1 = theme default)
                reaper.SetThemeColor("col_cursor" ,tonumber(api.load("Play mode","col_cursor")) or -1,0)
                reaper.SetThemeColor("col_cursor2",tonumber(api.load("Play mode","col_cursor2")) or -1,0)
            end
            
            reaper.UpdateTimeline()
            reaper.SetExtState("Play mode","Play mode",math.abs(pause_mode-1),false)
        
        end
    
    end

    -----
    reaper.ClearConsole()
    if  api.load('practice mode','snapshot') == '1' then
        api.cmd(40044,0)--next snapshot
    else
        Play=reaper.GetPlayState()
        if  Play==5 then
            main()
        else
            reaper.defer(function()main()end)
        end
    end
    
    
