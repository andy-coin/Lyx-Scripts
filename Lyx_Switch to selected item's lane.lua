
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")

    local function main()

        local item,track,lane_n
        api.mcw()
        item = api.mci()
        
        if not item then return end
    
        track = api.git(item)
        api.sot(track)

        lane_n = api.gtv(track,"I_NUMFIXEDLANES")
        
        if  lane_n > 1 and api.gtv(track,"C_LANESCOLLAPSED")==0 then
            api.cmd(42478,0)--play lanes under mouse
            for abi=1,lane_n do
                if  api.gtv(track,"C_LANEPLAYS:"..(abi-1))==1 then 
                    --change name
                    _,tr_name=api.ts(track,"P_NAME","",false)
                    _,lane_name=api.ts(track,"P_LANENAME:"..(abi-1),"",false)
                    new_name=tr_name:gsub("(   %[ .* %])","").."   [ "..lane_name..' ]'
                    api.ts(track,"P_NAME",new_name,true)
                    break
                end
            end
            return
        end
    end

    main()

    reaper.defer(function()end)
