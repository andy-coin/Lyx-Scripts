
    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    local function main()

        api.mcw()
        local item = api.mci()

        if api.csi(0) > 1 then 
            api.cmd(40009,0)
            return
        end

        if not item then return end

        local take = api.gatk(item)
        
        if not take then 
            api.cmd(40850,0)    
        else
            local source, Type, path
            source = reaper.GetMediaItemTake_Source(take)
            Type = reaper.GetMediaSourceType(source)
            path = reaper.GetMediaSourceFileName(source)
            
            if Type =='RPP_PROJECT' then
                reaper.Main_OnCommand(41929,0) -- New project tab (ignore default template)
                reaper.Main_openProject(path)
            else
                api.cmd(40009,0)
            end
        end

    end
    
    main()
    
    reaper.defer(function() end)