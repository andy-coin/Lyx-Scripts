
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    local hold_time, ING,now,trackzzz,razor,razor_data,solo_tr,P,E,p
    
    hold_time = 0.3
    
    --------------
    local function SaveCurrentState()

        trackzzz=r.SaveTracks()
        razor,razor_data=r.GetRazorEdits(false)
        local mouse_tr=reaper.BR_TrackAtMouseCursor()
        solo_tr=(razor and razor_data.track) or (#trackzzz<=1 and {mouse_tr}) or trackzzz

        if  not solo_tr then return nil end
        --set play cursor and play        
        P=reaper.GetPlayState()
        E=reaper.GetCursorPosition()
        p= (razor and razor_data.min) or reaper.BR_PositionAtMouseCursor(false)
        p=(p~=-1 and p) or E
        if  P==0 then
            reaper.SetEditCurPos(p,false,false)
            reaper.Main_OnCommand(1007,0)--play
        else
            reaper.SetEditCurPos(p,false,true)
        end
        reaper.SetEditCurPos(E,false,false)
        --set soloing state
        api.save("holding solo","state",1,false)
        api.save("holding solo","time",now+0.4,false)

    end 

    --------------
    local function SoloUnserMouseTracks(E,P)
        
        local time=api.load("holding solo","time")
        time=(time~="" and tonumber(time)) or reaper.time_precise()
        local now=reaper.time_precise()

        if  now-time <= hold_time then
            reaper.defer(function() SoloUnserMouseTracks(E,P) end)
        else
            if  P == 0 then reaper.Main_OnCommand(1016,0) end --stop
            local guid  = api.load("holding solo", 'last mouse track')
            local lane  = api.load("holding solo", 'last mouse track lane')
            local last_mouse_tr = api.idt(0, guid)
            if api.check(0, last_mouse_tr, 'MediaTrack*') and tonumber(lane) then
                api.stv(last_mouse_tr, 'C_LANEPLAYS:' .. (lane-1), 1)
            end
            local cmd=reaper.NamedCommandLookup("_BR_RESTORE_SOLO_MUTE_ALL_TRACKS_SLOT_3")
            reaper.Main_OnCommand(cmd,0)
            api.save("holding solo","state","0",false)
            reaper.DeleteExtState("holding solo","time",true)
            return
        end
    end
    
    --------------

    ING=api.load("holding solo","state")
    now=reaper.time_precise()

    if  ING ~= "1" or api.gps() == 0 then --new instance
        SaveCurrentState()
        if not solo_tr then return end
        local cmd=reaper.NamedCommandLookup("_BR_SAVE_SOLO_MUTE_ALL_TRACKS_SLOT_3")
        reaper.Main_OnCommand(cmd,0)--save solo tracks
        reaper.Main_OnCommand(40340,0)--unsolo all tracks
        reaper.Main_OnCommand(40297,0)--unselect all tracks
        api.mcw()
        mouse_tr = api.mct()

        for abi=1,#solo_tr do
            local tr = solo_tr[abi]
            reaper.SetTrackSelected(tr,true)
            if mouse_tr == tr then
                lane_n = api.gtv(tr,"I_NUMFIXEDLANES")
                for abig=1, lane_n do
                    if  api.gtv(tr,"C_LANEPLAYS:"..(abig-1)) == 1 then
                        local guid = api.tid(tr)
                        api.save("holding solo", 'last mouse track', guid, false)
                        api.save("holding solo", 'last mouse track lane', abig, false)
                        break
                    end
                end
                api.cmd(42478,0) -- Play only lane under mouse
            end
        end

        reaper.Main_OnCommand(40728,0)--solo tracks
        r.RestoreTracks(trackzzz)
        SoloUnserMouseTracks(E,P)
    else -- soloing
        api.save("holding solo","time",now,false)
    end--]]

