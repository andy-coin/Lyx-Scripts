    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    send_idx = 7

    local function main()

        for abi = 1, api.cst(0) do
            local tr = api.gst(0,abi-1)
            if  send_idx <= reaper.GetTrackNumSends(tr,0) then
                local mute = api.gtsv(tr,0,send_idx-1,"B_MUTE")
                api.stsv(tr,0,send_idx-1,'B_MUTE',math.abs(mute-1))
            end
        end

    end

    reaper.defer(main)