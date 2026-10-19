    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    local function main()

        --local trackzzz=r.SaveTracks()

        reaper.BR_GetMouseCursorContext()
        local tr = reaper.BR_GetMouseCursorContext_Track()

        --r.RestoreTracks(trackzzz)
        if  tr then
            api.sts(tr,not reaper.IsTrackSelected(tr))
        end

    end

    main()