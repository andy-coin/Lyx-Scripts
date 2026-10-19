
    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*/)") or "./"
    script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r = require("_Lyx_HOME")

    now = api.now()

    -----CUSTOM-----
    threshold = 10 -- second

    local function defer()

        local state = api.load('Midi_editor','move note state')

        if not api.M() or (state ~= '1' and state ~= 'ON') or ( api.now()-now) > threshold then 
            reaper.DeleteExtState('Midi_editor','move note state',true)
            BBB('Move Note  [' .. 'OFF' .. ']',threshold)
            return 
        end

        reaper.defer(defer)
        
    end
    
    local function main()
        
        local state = api.load('Midi_editor','move note state')

        if not state or state == '' then
            api.save('Midi_editor','move note state','1',false)
        else
            api.save('Midi_editor','move note state',math.abs(state-1),false)
        end

        local toggle= (state == '1' and 'OFF') or 'ON'

        BBB('Move Note  [' .. toggle .. ']',threshold-1)

        if toggle == 'ON' then defer() end

    end

    main()

    reaper.defer(function()end)