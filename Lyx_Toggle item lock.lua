  
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
  
    --------------
    local function main()
        
        local locked, cmd, base_on_proj, base_on_time, TimeBase
        
        locked=0
        
        for abi=1,reaper.CountSelectedMediaItems(0) do
            local item=reaper.GetSelectedMediaItem(0,abi-1)
            locked=reaper.GetMediaItemInfo_Value(item,"C_LOCK")
            if locked==1 then break end
        end
        
        cmd=40688+locked
        
        base_on_time = api.name('_SWS_AWITEMTBASETIME')
        base_on_proj = api.name('_SWS_AWITEMTBASEPROJ')

        TimeBase = ( locked == 1 and base_on_proj ) or base_on_time

        reaper.Main_OnCommand(cmd,0)--lock/unclok
        reaper.Main_OnCommand(TimeBase,0)--lock/unclok
        
        reaper.UpdateArrange()
    end
    
    reaper.Undo_BeginBlock()
    main()
    reaper.Undo_EndBlock("Toggle items lock",-1)
