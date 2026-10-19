
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    -----CUSTOM-----
    local dim_value = 24


    local function main()

        local toggle,master,master_volume

        toggle = api.load('DIM','toggle'..pro_name)
        toggle = (toggle == '0.2' and 5 ) or 0.2

        master = api.gmt(0)

        master_volume = api.gtv(master,'D_VOL')

        api.stv(master,'D_VOL',master_volume * toggle )

        api.save('DIM','toggle'..pro_name,toggle,false)

    end
    
    reaper.defer(main)
