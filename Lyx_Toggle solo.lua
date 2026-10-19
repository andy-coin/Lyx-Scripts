  
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
            
    --------------
    local function SaveSoloTracks()
        r.SaveTracks(true)
        api.cmd(api.name('_SWS_SELSOLOEDTRACKS'),0)--select solo tracks
        for abi = api.cst(0), 1, -1 do
            local tr = api.gst(0,abi-1)
            if  api.gtv(tr, 'B_SOLO_DEFEAT') == 1 then
                api.sts(tr, false)
            end
        end
        r.SaveTracks('solo_tracks')
        r.RestoreTracks(true)
    end
    
    --------------
    local function main()
    
        if  reaper.AnyTrackSolo(0) then -- any solo tracks
            
            SaveSoloTracks()
            --api.cmd(api.name('_BR_SAVE_SOLO_MUTE_ALL_TRACKS_SLOT_16'),0)-- save soloed tracks' solo state slot 16     
            api.cmd(40340, 0)-- unsolo all tracks
            
        else
            
            r.SaveTracks(true)
            r.RestoreTracks('solo_tracks')
            --api.cmd(40728,0)
            api.cmd(7,0)
            --api.cmd(api.name('_BR_RESTORE_SOLO_MUTE_ALL_TRACKS_SLOT_16'),0) -- restore solo and mute states slot 16
            r.RestoreTracks(true)
        end
        
    end
        
    -----
    
    reaper.defer(main)
