    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    -----CUSTOM-----
    cycle = true

    -------------
    local function checkType(item)
        
        if  item then 
            local take = reaper.GetActiveTake(item)
            if take and reaper.TakeIsMIDI(take) then
                T = 'midi'
            elseif take and reaper.GetMediaItemTake_Source(take) then
                T = 'audio'
            end
        end

        return T

    end
    
    local function main()

        item_n = api.csi(0)

        if item_n == 0 then return end

        for abi = 1, item_n do

            local item = api.gsi(0, abi-1)

            if not audio and checkType(item) == 'audio' then audio = true end
            if not midi  and checkType(item) == 'midi'  then midi  = true end

        end

        if midi and audio then return end

        if midi then

            api.cmd(40126, 0) --Take: Switch items to previous take

        elseif audio then

            api.cmd(42707, 0) --Fixed lane comp area: Move comp area up for selected items

        end

    end

    main()