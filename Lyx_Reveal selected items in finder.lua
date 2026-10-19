    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    local function main()

        if api.cst(0) == 0 then return end
        
        api.cmd(api.name("_S&M_OPEN_ITEM_PATH"),0)

    end


    main()