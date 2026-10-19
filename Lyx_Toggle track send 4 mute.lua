    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    send_idx = 4

    local function main()

        tr = api.gst(0,0)

        mute = api.gtsv(tr,0,send_idx-1,"B_MUTE")

        api.stsv(tr,0,send_idx-1,'B_MUTE',math.abs(mute-1))

    end

    reaper.defer(main)