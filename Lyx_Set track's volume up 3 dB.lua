    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    --script_path=script_path:gsub("[/\\]MIDI Editor[/\\]$","/")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
    
    --------------
    local function main()
        
        reaper.Undo_BeginBlock()

        r.SelTrackFilter()
        
        if api.cst(0) == 0 then return end
        
        dB_data = {}
        for abi=1,api.cst(0) do
            local tr = api.gst(0,abi-1)
            vol = api.gtv(tr,"D_VOL")
            dB = r.Vol_to_dB(vol)
            dB = r.NumberCage(dB+3,-96,12,1)
            dB_data[abi] = dB
            vol = r.dB_to_Vol(dB)
            api.stv(tr,'D_VOL',vol)
        end

        all_match = true
        for abi=1,#dB_data-1 do
            if  dB_data[abi]~=dB_data[abi+1] then
                all_match= false
                break
            end
        end

        if  all_match then
            r.billboard("Set track volume to "..dB_data[1]..' dB')
        else
            r.billboard('Set track\'s volume up 3 dB')
        end

        reaper.Undo_EndBlock("Set selected tracks volume +3 dB",-1)
        
    end
    
    reaper.defer(main)
