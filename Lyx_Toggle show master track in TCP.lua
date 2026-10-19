

    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    local function main()
        
        tracks = r.SaveTracks(true)

        TCP_tempo = 41050
        --if  reaper.GetToggleCommandState(TCP_tempo) then
        api.cmd(41050,0)
        master = api.gmt()
        api.sot(master)
        api.cmd(40406,0)--show volume envelope (was a custom action: 40406 + WOL lane + WOL height slot 1)
        api.cmd(api.name('_WOL_PUTSELENVINENVLANE'),0)
        api.cmd(api.name('_WOL_APPHSELENVSLOT1'),0)
        --end

        r.RestoreTracks(true)
    end

    main()

    reaper.defer(function()end)