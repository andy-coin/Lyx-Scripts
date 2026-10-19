    
    local script_path = debug.getinfo(1).source:match("@?(.*[/\\])") or "./"
    package.path = package.path..";"..script_path.."?.lua"
    local r=require("_lib._Lyx_HOME") 
    
    hold_title = "scrolling cursor"
    
    local function GotoCursor()
        
        local function CloseFX()
        
            local windows={"FX: Track","FX: Item","FX: Monitoring","VST:","VSTi:",
                            "VST3:","VST3i:","AU:","AUi:","LV2:","LV2i:","JS:",
                            "CLAP:","CALPi:","ReWire:"}--,"(input FX chain)"}
            
            for abi=1,#windows do
                local hwnd=reaper.JS_Window_Find(windows[abi],false)
                while hwnd do
                    reaper.JS_Window_Destroy(hwnd)
                    hwnd=reaper.JS_Window_Find(windows[abi],false)
                end
                if hwnd then floating=true end
            end
            
            return floating 
        
        end
        
        --CloseFX()
        
        if  not floating then
            Start,End=reaper.GetSet_ArrangeView2(0,false,0,0,0,0)
            E=api.gec()
            P=api.gpc()
            play=api.gps()
            
            e_cur = ( E>=Start and E<=End)
            p_cur = ( P>=Start and P<= End)
            Both = e_cur and p_cur
            
            if  play%2~=0 then --playing
                if  Both or not p_cur then
                    api.cmd(api.name("_SWS_HSCROLLPLAY10"),0)
                else
                    api.cmd(40151,0)
                end
            else --stop
                api.cmd(api.name("_SWS_HSCROLL10"),0)
                return
            end
        end
        
    end
    
    --------------
    local function SaveCurrentState()

        reaper.SetExtState(hold_title,"state",1,false)
        reaper.SetExtState(hold_title,"time",now+0.4,false)

    end

    --------------
    local function Set_Auto_Scroll()
        
        local time=reaper.GetExtState(hold_title,"time")
        time=(time~="" and tonumber(time)) or reaper.time_precise()
        local now=reaper.time_precise()

        if  now-time<=0.1 then
            reaper.defer(function() Set_Auto_Scroll() end)
        else
            if  scrolling==1 then
                reaper.Main_OnCommand(40036,0)
            end
            reaper.SetExtState(hold_title,"state","0",false)
            reaper.DeleteExtState(hold_title,"time",true)
            return
        end
    end
    
    --------------

    ING=reaper.GetExtState(hold_title,"state")
    now=reaper.time_precise()
    scrolling = reaper.GetToggleCommandState(40036)
    if  ING~="1" then --new instance
        GotoCursor()
        SaveCurrentState()
        Set_Auto_Scroll()
    else -- soloing
        if  scrolling==0 then
            reaper.Main_OnCommand(40036,0)
        end
        reaper.SetExtState(hold_title,"time",now,false)
    end--]]
