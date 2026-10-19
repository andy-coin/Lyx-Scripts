    local script_path = debug.getinfo(1).source:match("@?(.*/)") or "./"
    --script_path=script_path:gsub("/MIDI Editor","")
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_Lyx_HOME")
  
    
    -----CUSTOM-----
    
        ---buffer size-
        auto_change_buffersize = false
        small = 128
        large = 2048
    
    local function ChangeBufferSize(size)
        
        local pro_n = r.CountProjects()
        if  pro_n > 1 then
            for abi=1,pro_n do 
                if  reaper.GetPlayState(abi-1)~=0 then 
                    running=true
                    break
                end
            end
        end
    
        if  not running then
            r.SetBufferSize(size)
        end
    end 
    
    local function main()
        
        arm = api.gtc(40740)
         
        for  abi=1,api.ct(0) do
            
            tr = api.gt(0,abi-1)
            
            --if  api.itv(tr,false) then 
                if  api.gtv(tr,"I_RECINPUT")==6112 then
                    api.stv(tr,'I_RECMON',math.abs(arm-1))
                end
            --end
        end
        
        api.cmd(40740,0)--toggole all tracks record auto arm
         
        BufferSize = ( arm == 1 and large) or small
        if  auto_change_buffersize then ChangeBufferSize(BufferSize) end
        

    end

    main()

    reaper.defer(function()end)
