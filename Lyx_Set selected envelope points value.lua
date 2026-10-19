
    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*/)") or "./"
    script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    SHAPE = { ['0']=1, ['1']=0, ['2']=3, ['3']=4, ['4']=2, ['5']=5}
    
    local function main()

        local env, Value, Shape, ai_idx, _, name

        env = api.gse()

        if not env then return end
        
        _,name = api.gen(env)
        --msg(name)

        local ret,csv=r.GetUserInputs(
                "Set Envelope Points",2,"Value : \30Curve shape : \30extrawidth=175\30separator=\30",
                '\30 [0=⎍] , [1=／] , [2=⎛] , [3=⎠] , [4=∫] , [5=ß]\30')

        if not ret then return end 

        local answer = {}
        for str in csv:gmatch("[^\30]*") do
            answer[#answer+1]= str
        end
        
        Value = answer[1]
        Shape = SHAPE[answer[2]]
        
        if  Value and #Value>0 then
            if  Value:find("%+") then
                Value = tonumber(Value)
            elseif Value == "-" then
                Value = -144
            else
                Value = math.abs(tonumber(Value)) * -1
            end

            if  name:find("Volume") then
                Value = r.dB_Value(Value) 
            end
        else
            Value = nil
        end

        r.Undo("Set selected envelope points value", function()
            ai_idx = api.cai(env)

            for abi = -1 ,ai_idx-1 do
                local p_idx = api.cep(env,abi)
                for abii = 0, p_idx do
                    local retval, time, value, shape, tension, selected = api.gep(env, abi, abii)
                    if  retval and selected then
                        --msg(value)
                        api.sep(env, abi, abii, time, Value or value, Shape or shape, tension, selected, true)
                    end
                end
                api.esp(env, abi)
            end
            api.ua()
        end)
    end

    api.cc()
    r.run(main)
