    
    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")

    -----CUSTOM-----
        default_icon = reaper.GetResourcePath()..'/Data/track_icons/Logic/audio.png'  
        default_icon = ''  


    local function SetTrackicon()            
            
        local data = api.load('Track Icon',pj_name)
  
        if  data =='' then
            for abi=1,api.ct(0) do
                tr = api.gt(0,abi-1)
                api.ts(tr,'P_ICON',default_icon,true)
            end
            return
        end
        
        for track_data in data:gmatch('([^\31]*)') do
            local guid,icon,tr
            guid = track_data:sub(1,38)
            icon = track_data:sub(40,-1)
            icon = (icon ~= '' and icon) or default_icon
            tr = api.idt(0,guid)
            if  api.check(0,tr,'MediaTrack*') then
                api.ts(tr,'P_ICON',icon,true)
            end
        end

    end

    local function ClearTrackicon()
        local data = ''
        for abi=1,api.ct(0) do
            local tr = api.gt(0,abi-1)
            guid = api.tid(tr)
            _,icon = api.ts(tr,'P_ICON','',false)
            data = data .. guid ..'\30' .. icon .. '\31'
            api.ts(tr,'P_ICON','',true)
        end
        api.save('Track Icon',pj_name,data,true)
    end

    local function main()
        
        pj_name = api.gpn(0)
        pj_name = (pj_name ~= '' and pj_name ) or 'Unsaved project'
        
        for abi=1,api.ct(0) do
            local tr = reaper.GetTrack(0,abi-1)
            _ , icon = reaper.GetSetMediaTrackInfo_String(tr,"P_ICON","",false)
            if  icon ~= '' then
                clear= true
                break
            end
        end
        
        if  clear then 
            ClearTrackicon()
        else
            SetTrackicon()
        end
        
    end
    
    main()
    reaper.defer(function()end)
