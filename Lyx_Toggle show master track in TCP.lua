

    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    local function main()
        
        tracks = r.SaveTracks(true)

        TCP_tempo = 41050
        --if  reaper.GetToggleCommandState(TCP_tempo) then
        api.cmd(41050,0)
        master = api.gmt()
        api.sot(master)
        api.cmd(api.name('_1d978b78de314723a612d2b159ac8482'),0)--show volume envelope
        --end

        r.RestoreTracks(true)
    end

    main()

    reaper.defer(function()end)