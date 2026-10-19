
    local script_name = debug.getinfo(1).source
    local script_path = script_name:match("@?(.*/)") or "./"
    script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    -----CUSTOM-----
    
    speed = 0.2

    local function main()
        
        editor = api.M()

        if api.gtc(40036) == 1 then api.cmd(40036, 0) end
        
        if  reaper.GetToggleCommandStateEx(32060, 40640) == 1 then
            api.Mcmd(editor, 40640) -- midi editor Timebase: Toggle sync to arrange view
        end
        
        _,_,_,_,_,_,mouse_wheel  = reaper.get_action_context() 
        
        times = math.abs(math.floor(mouse_wheel*speed))
        
        api.cc()
        msg(times)

        api.Mcmd(editor,40433)

    --     if mouse_wheel>0 then
    --         for abi=1,times do
    --             api.Mcmd(editor,40140)
    --         end
    --     else
    --         for abi=1,times do
    --             api.Mcmd(editor,40141)
    --         end
    --     end
        
    end
    
    reaper.defer(main)
