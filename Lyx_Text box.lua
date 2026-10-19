
    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME") 
    
    local function main()
        
            local ret,csv = r.GetUserInputs("Text Box",1,"write some shit\30extrawidth=125\30separator=\30",
                        '\30')

            if not ret or #csv==0 then return end
            
            reaper.CF_SetClipboard(csv)
    end

    r.run(main)

    reaper.defer(function()end)
