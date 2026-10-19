  
    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME")
    
    --------------
    local function main()
        
        r.SelTrackFilter()
        
        if api.cst(0) == 0 then return end

        reaper.Undo_BeginBlock()
        
        pan_data = {}
        for abi=1,api.cst(0) do
            local tr = api.gst(0,abi-1)
            pan = api.gtv(tr,"D_PAN")
            pan = r.NumberCage(pan-0.25,-1,1,4)
            FC = (pan < 0 and math.ceil) or math.floor
            pan_data[abi] = FC(pan*100)
            api.stv(tr,'D_PAN',pan)
        end

        all_match = true
        for abi=1,#pan_data-1 do
            if  pan_data[abi]~=pan_data[abi+1] then
                all_match= false
                break
            end
        end

        if  all_match then
            local direction = (pan_data[1] < 0 and ' L') or ' R'
            r.billboard("Set track\'s pan to "..pan_data[1]..direction)
        else
            r.billboard('Set track\'s pan -25')
        end

        reaper.Undo_EndBlock("Pan track left",-1)
        
    end
    
    reaper.defer(main)
