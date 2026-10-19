    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    local function main()
        
        trz=r.SaveTracks()
        
        if  #trz==0 then return end
        
        for abi=1,#trz do
            
            local tr,midi,FX,fx,_,name,drum
            
            tr=trz[abi]
            midi=api.gtv(tr,"I_RECINPUT")>=4096
            
            if  not midi then goto NEXT end
            
            local FX=reaper.TrackFX_AddByName(tr,"JS: MIDI Transpose Track",true,0) -- input FX, any slot
            
            if  FX<0 then
                FX=reaper.TrackFX_AddByName(tr,"JS: MIDI Transpose Track",true,-1000)
                if  FX<0 then
                    reaper.MB('JSFX "MIDI Transpose Track" not found.\nInstall it via ReaPack (BinbinHfr repository).',"Lyx Scripts",0)
                    return
                end
                reaper.TrackFX_SetPresetByIndex(tr,0x1000000|FX,4)
            end
            FX=0x1000000|FX
            
            fx = reaper.TrackFX_GetInstrument(tr)
            
            if fx == -1 then goto NEXT end
            
            _,name = reaper.TrackFX_GetFXName(tr,fx~=-1 and fx)

            drum = (name:match("Superior Drummer 3") and -1) or 1 

            local octave=reaper.TrackFX_GetPresetIndex(tr,FX)
            
            if  octave~=0 then
                reaper.TrackFX_SetPresetByIndex(tr,FX,octave-1)--drum)
            end
            
            ::NEXT::
        end
        
    end

    main()
    reaper.defer(function() end)
