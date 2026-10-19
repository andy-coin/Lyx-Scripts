
    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    ------------
    ---CUSTOM---
    ------------
        mic = 1026 -- 3 & 4
        playback = 1030 -- 7 & 8
        eg_input = 1038 -- 15 & 16
    
    ---------------------
    local function main()
        
        FX,tr_n,it_n,fx_n = reaper.GetFocusedFX2() 
        
        if  FX==0 or FX>=4 then
            
            Act = "Switch track input"
            tr_n = api.cst(0)
            if tr_n == 0 then return end

            for abi=1,tr_n do
                local tr = api.gst(0,abi-1)
                local input=api.gtv(tr,"I_RECINPUT")
                ::again::
                if  input >= 0 and input < 1024 then 
                    if input >= 17 then 
                        input = 0
                    else 
                        input = (input == 3 and 17 ) or input + 1 
                    end
                    api.stv(tr,"I_RECINPUT",input)
                    --reaper.SetMediaTrackInfo_Value(tr,"I_RECMON",1)
                elseif input == mic then 
                    api.stv(tr, 'I_RECINPUT', eg_input)
                -- elseif input == eg_input then
                    -- api.stv(tr, 'I_RECINPUT', playback)
                    -- api.stv(tr,"I_RECMON",0)
                    -- api.stv(tr,"I_SOLO", 1)
                elseif input == playback then
                    api.stv(tr, 'I_RECINPUT', 1024)
                elseif input >= 1024 and input < 4096 then 
                   input = (input >= 1038 and 1024) or input + 2
                   api.stv(tr,"I_RECINPUT",input)
                   if input == 1030 then
                       api.stv(tr,"I_RECMON",0)
                       api.stv(tr,"I_SOLO", 1)
                   end
                elseif input>=4096 then
                    if reaper.TrackFX_GetInstrument(tr)==-1 then
                        api.stv(tr,"I_RECINPUT",0)
                    end
                    mode=api.gtv(tr,"I_RECMODE")
                    if mode==7 then
                        api.stv(tr,"I_RECMODE",8)
                    elseif mode==8 then
                        api.stv(tr,"I_RECMODE",7)
                    end
                end
                if  input == 6 or input == 7 or input == 14 or input == 15 then goto again end --skip monitor feedback
            end

        elseif FX == 1 then
            
            Act="Switch track FX preset"
            tr=reaper.GetTrack(0,tr_n-1)
            preset,All=reaper.TrackFX_GetPresetIndex(tr,fx_n)
            if preset+1>=All then 
                preset=-1
            end
            reaper.TrackFX_SetPresetByIndex(tr,fx_n,preset+1)
            
        elseif FX == 2 then 
            
            Act="Switch take FX preset"
            tr=reaper.GetTrack(0,tr_n-1)
            item=reaper.GetTrackMediaItem(tr,it_n)
            take=reaper.GetActiveTake(item)
            preset,All=reaper.TakeFX_GetPresetIndex(take,fx_n)
            reaper.TakeFX_GetPreset(take,fx_n)
            if preset+1>=All then 
                preset=-1
            end
            reaper.TakeFX_SetPresetByIndex(take,fx_n,preset+1)
        end  
            
    end
    
    

    reaper.Undo_BeginBlock()
    main()
    reaper.Undo_EndBlock("Trigger next preset for FX of selected tracks",-1)
    
