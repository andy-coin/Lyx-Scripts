
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    local FX_windows  ={"FX: Track","FX: Item","FX: Monitoring","VST:","VSTi:",
    "VST3:","VST3i:","AU:","AUi:","LV2:","LV2i:","JS:",
    "CLAP:","CALPi:","ReWire"}

    --------------
    local function WindowKiller(windows)

        local kill
        for abi=1,#windows do
            local hwnd=reaper.JS_Window_Find(windows[abi],false)
            if  hwnd then kill=true end
            while hwnd do
                reaper.JS_Window_Destroy(hwnd)
                hwnd=reaper.JS_Window_Find(windows[abi],false)
            end
        end
        return kill

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
            WindowKiller(FX_windows)
            return
        end

        FX_position =api.name("_RS021abfa884464328e69a553804fb169e9b7ba370")
        api.cmd(FX_position,0)

    end
    
    main()
    reaper.defer(function()end)