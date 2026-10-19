
    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*[/\\])") or "./"
    script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
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
        
        local items, take, editor, n

        reaper.Undo_BeginBlock()

        -- prefer the takes open in the MIDI editor; fall back to selected items
        editor = api.M()
        n = 0
        if  editor then
            take = reaper.MIDIEditor_EnumTakes(editor, n, true)
            while take do
                SetShape(take)
                n = n + 1
                take = reaper.MIDIEditor_EnumTakes(editor, n, true)
            end
        end

        if  n == 0 then
            
            items= r.SaveItems()
            for abi = 1, #items do
                take = api.gatk(items[abi])
                if  take and reaper.TakeIsMIDI(take) then
                    SetShape(take)
                end
            end

        end

        reaper.Undo_EndBlock('Set selected CC curve shape to '..shape, -1)

    end

    main()