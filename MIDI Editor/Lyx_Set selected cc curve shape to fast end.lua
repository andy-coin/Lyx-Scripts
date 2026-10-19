
    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*/)") or "./"
    script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    SHAPE = {["square"]=0, ["linear"]=1, ["S curve"]=2, ["fast start"]=3, ["fast end"]=4, ["bezier"]=5 }
    
    shape = script_name:match("to (.-)%.lua")

    local function SetShape(take)
        
        local cc = reaper.MIDI_EnumSelCC(take, -1)
        
        while cc ~= -1 do
            
            local last_cc = cc
            reaper.MIDI_SetCCShape(take,cc,SHAPE[shape],0.5,true)
            cc = reaper.MIDI_EnumSelCC(take, last_cc)
            if last_cc == cc then break end

        end
        
        reaper.MIDI_Sort(take)

    end

    local function main()
        
        local items, take, editor
        
        items= r.SaveItems()

        if  #items ~= 0 then
            
            for abi = 1, #items do
                
                local item, take
                
                item = items[abi]
                take = api.gatk(item)

                if  take then
                    SetShape(take)
                end
                
            end

        else
            
            editor = api.M()
            take = api.Mgt(editor)

            if  take then
                SetShape(take)
            end

        end

    end

    main()