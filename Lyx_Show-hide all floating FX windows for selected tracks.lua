
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    --------------
    -- Close every floating FX window and FX chain window (track, input/monitoring, take FX)
    local function CloseAllFXWindows()

        local function CloseTrack(track)
            for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
                reaper.TrackFX_Show(track, fx, 2)
            end
            for fx = 0, reaper.TrackFX_GetRecCount(track) - 1 do
                reaper.TrackFX_Show(track, fx + 0x1000000, 2)
            end
            if  reaper.TrackFX_GetChainVisible(track) ~= -1 then reaper.TrackFX_Show(track, 0, 0) end
            if  reaper.TrackFX_GetRecChainVisible(track) ~= -1 then reaper.TrackFX_Show(track, 0x1000000, 0) end
        end

        CloseTrack(reaper.GetMasterTrack(0))
        for t = 0, reaper.CountTracks(0) - 1 do
            CloseTrack(reaper.GetTrack(0, t))
        end
        for i = 0, reaper.CountMediaItems(0) - 1 do
            local item = reaper.GetMediaItem(0, i)
            for tk = 0, reaper.CountTakes(item) - 1 do
                local take = reaper.GetTake(item, tk)
                if  take then
                    for fx = 0, reaper.TakeFX_GetCount(take) - 1 do
                        reaper.TakeFX_Show(take, fx, 2)
                    end
                    if  reaper.TakeFX_GetChainVisible(take) ~= -1 then reaper.TakeFX_Show(take, 0, 0) end
                end
            end
        end

    end

    --------------
    local function GetAllFloatingFXWindows()
    
        local hwnds = {}
        
        local master_track
        
        master_track = reaper.GetMasterTrack(0)
        
        for fx = 0, reaper.TrackFX_GetCount(master_track) - 1 do
            local hwnd
            hwnd = reaper.TrackFX_GetFloatingWindow(master_track,fx)
            if  hwnd then
                hwnds[#hwnds+1]=hwnd
            end
        end
        
        for t = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, t)    
            for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
                local hwnd
                hwnd = reaper.TrackFX_GetFloatingWindow(track, fx)
                if  hwnd then
                    hwnds[#hwnds+1]=hwnd
                end
            end

            for fx = 0, reaper.TrackFX_GetRecCount(track) - 1 do
                local fx_in,hwnd
                fx_in = fx + 0x1000000
                hwnd = reaper.TrackFX_GetFloatingWindow(track,fx_in)
                if  hwnd then
                    hwnds[#hwnds+1]=hwnd
                end
            end
        end
        
        return #hwnds
    end

    --------------
    local function main()
    
        local FXs,show_plugins,FX_position
        
        FXs=GetAllFloatingFXWindows()

        show_plugins=api.name("_S&M_WNTSHW3")
        api.cmd(show_plugins,0)
        if  FXs == GetAllFloatingFXWindows() then
            CloseAllFXWindows()
            return
        end

        FX_position =r.ScriptID("Lyx Scripts/Lyx_Smart set FX windows position.lua")
        api.cmd(FX_position,0)

    end
    
    main()
    reaper.defer(function()end)