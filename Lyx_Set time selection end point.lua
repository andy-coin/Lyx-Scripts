
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    local function main()
        api.pur(1)
        local starttime, endtime = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
        local loop = reaper.GetToggleCommandState(1068) == 1
        if not loop then api.cmd(1168,0) end
        local cursor = api.gec()
        reaper.GetSet_LoopTimeRange2(0, true, loop, starttime, cursor, false)
        api.pur(-1)
        reaper.UpdateTimeline()
    end

    main()
    reaper.defer(main)
