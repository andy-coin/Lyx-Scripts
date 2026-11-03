
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    local r=require("_lib._Lyx_HOME")
    
    -----CUSTOM-----
    
        ---buffer size-
        auto_change_buffersize = false
        small = 128
        large = 2048

    --------------
    local function ChangeBufferSize()
    
        for abi=1,reaper.CountTracks(0) do
            local tr=reaper.GetTrack(0,abi-1)
            if  api.gtv(tr,"I_RECARM")==1 then
                r.SetBufferSize(small)
                return
            end
        end
        
        r.SetBufferSize(large)

    end

    local function toggle_track_arm(tr)
                        
        if  reaper.TrackFX_GetInstrument(tr) >= 0 then
            api.stv(tr,"I_RECINPUT",6112)
        end
        
        api.stv(tr,"I_RECARM",rec_arm)
        input = api.gtv(tr,"I_RECINPUT")
        if  input ~= 1030 then
            if  input == 6112 then
                api.stv(tr,"I_RECMON",rec_arm)
            end
        else
            api.stv(tr,'I_SOLO',rec_arm)
        end
    end
    --------------
    local function main()
        
        r.SelTrackFilter()

        if api.cst(0) == 0 then return end
        
        r.SaveTracks(true)

        
        ::NORMAL::

        rec_arm = (api.gtv(api.gst(0,0),"I_RECARM") == 0 and 1 ) or 0
        for abi=1,reaper.CountSelectedTracks(0) do
            local tr=reaper.GetSelectedTrack(0,abi-1)
            toggle_track_arm(tr)
        end

        r.RestoreTracks(true)

        ::CHANGE_BUFFER::
        play = reaper.GetPlayState()
        if play==0 and auto_change_buffersize then
            ChangeBufferSize()
        end

    end
    api.cc()

    main()
