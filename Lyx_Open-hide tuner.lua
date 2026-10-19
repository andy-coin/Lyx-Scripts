    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    -----CUSTOM-----
    ---monitor position, start from 0

    local function FindNonMon()

        api.cmd(api.name('_SWS_SELRECARM'),0)--select only record-armed track
        
        local MON = '' 
        local mon_tr = {}
        for abi = 1,api.cst(0) do
            local tr = api.gst(0,abi-1)
            if  api.gtv(tr,'I_RECMON') == 0 and api.gtv(tr,'I_RECINPUT') ~= 1030 then
                api.stv(tr,'I_RECMON',1)
                mon_tr[#mon_tr+1] = tr
            end
        end
        return mon_tr
    end

    local function main()
        
        local master,tuner,mon,trackzzz
        
        master=reaper.GetMasterTrack(0)
        tuner = 0x1000000
        
        mon = api.load('FX state','tuner mode')
        mon = tonumber(mon) or 0
        
        trackzzz = r.SaveTracks()
        
        for abi=1, #trackzzz do
            tr = trackzzz[abi]
            mode = api.gtv(tr,"I_RECMODE")
            if mode == 7 or mode == 8 then return end
        end
        
        if  not reaper.TrackFX_GetOpen(master,tuner) then   --not open
            --local trz = FindNonMon()
            reaper.TrackFX_Show(master,tuner,3)
            r.SaveTracks('Tuner')
        else                                            -- already open
            reaper.TrackFX_Show(master,tuner,2) 
            r.RestoreTracks('Tuner')
            for abi=1,api.cst(0) do
                local tr = api.gst(0,abi-1)
                --api.stv(tr,'I_RECMON',0)
            end
        end
        
        r.RestoreTracks(trackzzz)

    end
    
    reaper.defer(main) 
    
    local function TunerApp()
        
        os.execute('if pgrep -fq "Universal Tuner"; then pkill -f "Universal Tuner"; else open -a "Universal Tuner" && if pgrep -fq "Universal Tuner; then open -a "Reaper"; fi; fi')
    
    end
    
    --TunerApp()
    
